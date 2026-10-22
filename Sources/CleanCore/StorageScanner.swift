import Foundation

public enum StorageSizeMode: String, CaseIterable, Identifiable, Sendable {
    case allocated = "En disco", logical = "Tamaño lógico"
    public var id: String { rawValue }
}

public struct StorageEntry: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let isDirectory: Bool
    public let isLink: Bool
    public var logicalBytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
    public var fileCount = 0
    public var issueCount = 0
    public func bytes(_ mode: StorageSizeMode) -> Int64 { mode == .allocated ? allocatedBytes : logicalBytes }
}

public struct StorageProgress: Sendable {
    public var files = 0
    public var folders = 0
    public var allocatedBytes: Int64 = 0
    public var currentPath = ""
    public init() {}
}

public struct StorageResult: Sendable {
    public let root: URL
    public let entries: [StorageEntry]
    public let largestFiles: [StorageEntry]
    public let progress: StorageProgress
    public let warnings: [String]
    public let issueCount: Int
    public let cancelled: Bool
    public let finishedAt: Date
    public var logicalBytes: Int64 { entries.reduce(0) { $0 + $1.logicalBytes } }
    public var allocatedBytes: Int64 { entries.reduce(0) { $0 + $1.allocatedBytes } }
}

public enum StorageScanner {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey
    ]

    /// Walk metadata only. Never follows symlinks, reads file contents or crosses volumes.
    /// Retains immediate children and at most 100 large files, rather than the full file tree.
    public static func scan(root: URL, report: @Sendable (StorageProgress) -> Void = { _ in }) -> StorageResult {
        let manager = FileManager.default
        let base = root.standardizedFileURL
        var entries: [String: StorageEntry] = [:]
        var largestLogical: [StorageEntry] = []
        var largestAllocated: [StorageEntry] = []
        var progress = StorageProgress()
        var warnings: [String] = []
        var issueCount = 0
        var lastReport = Date.distantPast
        let prefix = base.path == "/" ? "/" : base.path + "/"

        func firstComponent(_ url: URL) -> String? {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { return nil }
            return path.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first.map(String.init)
        }
        func warn(_ url: URL, _ description: String) {
            issueCount += 1
            if warnings.count < 100 { warnings.append("\(url.path): \(description)") }
            if let name = firstComponent(url), entries[name] != nil { entries[name]?.issueCount += 1 }
        }
        func finish() -> StorageResult {
            var unique: [String: StorageEntry] = [:]
            for file in largestLogical + largestAllocated { unique[file.id] = file }
            report(progress)
            return StorageResult(root: base, entries: entries.values.sorted { $0.allocatedBytes > $1.allocatedBytes },
                                 largestFiles: Array(unique.values), progress: progress, warnings: warnings,
                                 issueCount: issueCount, cancelled: Task.isCancelled, finishedAt: Date())
        }
        func keepLargest(_ entry: StorageEntry, mode: StorageSizeMode, in list: inout [StorageEntry]) {
            guard list.count < 50 || entry.bytes(mode) > (list.last?.bytes(mode) ?? 0) else { return }
            list.append(entry)
            list.sort { $0.bytes(mode) > $1.bytes(mode) }
            if list.count > 50 { list.removeLast() }
        }

        do {
            let rootValues = try base.resourceValues(forKeys: keys)
            guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
                warn(base, "Selecciona una carpeta real, no un enlace simbólico.")
                return finish()
            }
            let rootVolume = rootValues.volumeIdentifier.map { String(describing: $0) }
            let children = try manager.contentsOfDirectory(at: base, includingPropertiesForKeys: Array(keys))
            for child in children {
                if Task.isCancelled { return finish() }
                do {
                    let values = try child.resourceValues(forKeys: keys)
                    entries[child.lastPathComponent] = StorageEntry(url: child, isDirectory: values.isDirectory == true,
                                                                  isLink: values.isSymbolicLink == true)
                } catch { warn(child, error.localizedDescription) }
            }
            guard let enumerator = manager.enumerator(at: base, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, error in
                warn(url, error.localizedDescription)
                return !Task.isCancelled
            }) else {
                warn(base, "No se pudo enumerar la carpeta.")
                return finish()
            }
            for case let url as URL in enumerator {
                if Task.isCancelled { break }
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    guard let name = firstComponent(url) else { continue }
                    // Files added after the initial listing may appear during enumeration.
                    if entries[name] == nil {
                        entries[name] = StorageEntry(url: base.appendingPathComponent(name),
                                                   isDirectory: url.deletingLastPathComponent().path != base.path || values.isDirectory == true,
                                                   isLink: values.isSymbolicLink == true)
                    }
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if let rootVolume, let volume = values.volumeIdentifier,
                       String(describing: volume) != rootVolume {
                        enumerator.skipDescendants()
                        warn(url, "Se omitió un volumen diferente.")
                        continue
                    }
                    if values.isDirectory == true { progress.folders += 1 }
                    if values.isRegularFile == true {
                        let logical = Int64(max(0, values.fileSize ?? 0))
                        let allocated: Int64
                        if let size = values.totalFileAllocatedSize { allocated = Int64(max(0, size)) }
                        else { allocated = 0; warn(url, "No se pudo medir el espacio asignado en disco.") }
                        entries[name]?.logicalBytes += logical
                        entries[name]?.allocatedBytes += allocated
                        entries[name]?.fileCount += 1
                        progress.files += 1
                        progress.allocatedBytes += allocated
                        var file = StorageEntry(url: url, isDirectory: false, isLink: false)
                        file.logicalBytes = logical
                        file.allocatedBytes = allocated
                        file.fileCount = 1
                        keepLargest(file, mode: .logical, in: &largestLogical)
                        keepLargest(file, mode: .allocated, in: &largestAllocated)
                    }
                    if Date().timeIntervalSince(lastReport) >= 0.25 {
                        progress.currentPath = url.path
                        report(progress)
                        lastReport = Date()
                    }
                } catch { warn(url, error.localizedDescription) }
            }
        } catch { warn(base, error.localizedDescription) }
        return finish()
    }
}
