import AppKit
import Darwin
import CleanCore
import Foundation

struct SystemSnapshot: Sendable {
    private static let host = mach_host_self()
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var compressed: UInt64 = 0
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var processes: [ProcessRow] = []
    var error: String?
    var memoryFraction: Double { Double(memoryUsed) / Double(max(memoryTotal, 1)) }

    static func read() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        var stats = vm_statistics64()
        var pageSize: vm_size_t = 0
        let pageStatus = host_page_size(Self.host, &pageSize)
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(Self.host, HOST_VM_INFO64, $0, &count)
            }
        }
        if status == KERN_SUCCESS, pageStatus == KERN_SUCCESS {
            let available = (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * UInt64(pageSize)
            snapshot.memoryUsed = snapshot.memoryTotal - min(available, snapshot.memoryTotal)
            snapshot.compressed = UInt64(stats.compressor_page_count) * UInt64(pageSize)
        } else { snapshot.error = "No se pudo consultar la memoria del sistema." }
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            snapshot.diskFree = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            snapshot.diskTotal = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid=,rss=,%cpu=,comm="]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                snapshot.error = "No se pudieron consultar los procesos."
                return snapshot
            }
            snapshot.processes = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").compactMap { line in
                let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                guard fields.count == 4, let pid = Int32(fields[0]), let rss = Int64(fields[1]),
                      let cpu = Double(fields[2]) else { return nil }
                let path = String(fields[3])
                return ProcessRow(id: pid, name: URL(fileURLWithPath: path).lastPathComponent,
                                  path: path, memory: rss * 1024, cpu: cpu)
            }.sorted { $0.memory > $1.memory }
        } catch { snapshot.error = error.localizedDescription }
        return snapshot
    }
}

func byteString(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
