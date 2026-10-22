import Foundation

public struct ProcessRow: Identifiable, Sendable {
    public let id: Int32
    public let name: String
    public let path: String
    public let memory: Int64
    public let cpu: Double
    public init(id: Int32, name: String, path: String, memory: Int64, cpu: Double) {
        self.id = id; self.name = name; self.path = path; self.memory = memory; self.cpu = cpu
    }
}

public struct MemoryGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleURL: URL?
    public var processes: [ProcessRow]
    public var memory: Int64 { processes.reduce(0) { $0 + $1.memory } }
    public var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }

    public static func group(_ rows: [ProcessRow]) -> [MemoryGroup] {
        var groups: [String: MemoryGroup] = [:]
        for row in rows {
            let bundle: URL?
            if let range = row.path.range(of: ".app/") {
                bundle = URL(fileURLWithPath: String(row.path[..<range.lowerBound]) + ".app")
            } else { bundle = nil }
            let key = bundle?.path ?? "process:\(row.id)"
            if groups[key] == nil {
                groups[key] = MemoryGroup(id: key, name: bundle?.deletingPathExtension().lastPathComponent ?? row.name,
                                          bundleURL: bundle, processes: [])
            }
            groups[key]?.processes.append(row)
        }
        return groups.values.map { group in
            var group = group
            group.processes.sort { $0.memory > $1.memory }
            return group
        }.sorted { $0.memory > $1.memory }
    }
}
