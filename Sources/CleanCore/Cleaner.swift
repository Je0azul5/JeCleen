import Foundation

public enum JunkCategory: String, CaseIterable, Identifiable, Sendable {
    case caches, logs
    public var id: String { rawValue }
    public var title: String { self == .caches ? "Cachés de aplicaciones" : "Registros antiguos" }
    public var symbol: String { self == .caches ? "shippingbox" : "doc.text" }
    public var detail: String {
        self == .caches
            ? "Archivos temporales sin cambios durante al menos 7 días."
            : "Registros de diagnóstico sin cambios durante al menos 7 días."
    }
}

public struct ScanRoot: Sendable {
    public let url: URL
    public let category: JunkCategory
    public init(url: URL, category: JunkCategory) { self.url = url; self.category = category }
    public static func userRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ScanRoot] {
        [.init(url: home.appendingPathComponent("Library/Caches"), category: .caches),
         .init(url: home.appendingPathComponent("Library/Logs"), category: .logs)]
    }
}

public struct JunkFile: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let root: URL
    public let category: JunkCategory
    public let bytes: Int64
    public let modified: Date
    public let fileIdentifier: String
}

public struct ScanResult: Sendable {
    public let files: [JunkFile]
    public let warnings: [String]
    public var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
}

public enum CleanerError: LocalizedError {
    case changed, outsideRoot, notRegular
    public var errorDescription: String? {
        switch self {
        case .changed: "El archivo cambió desde el análisis. Vuelve a analizar."
        case .outsideRoot: "La ruta está fuera de las carpetas analizadas."
        case .notRegular: "La ruta ya no es un archivo regular."
        }
    }
}

public enum Cleaner {
    public static let minimumAge: TimeInterval = 7 * 24 * 60 * 60
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
        .fileSizeKey, .fileResourceIdentifierKey
    ]

    public static func scan(roots: [ScanRoot], now: Date = Date()) -> ScanResult {
        let manager = FileManager.default
        var files: [JunkFile] = []
        var warnings: [String] = []
        for root in roots {
            if Task.isCancelled { break }
            let base = root.url.standardizedFileURL
            guard let rootValues = try? base.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
                  base.resolvingSymlinksInPath().path == base.path else {
                warnings.append("No se pudo revisar \(base.path). La carpeta no existe o no es accesible.")
                continue
            }
            guard let enumerator = manager.enumerator(at: base, includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants], errorHandler: { url, error in
                    warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    return true
                }) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { break }
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    guard values.isRegularFile == true,
                          let modified = values.contentModificationDate,
                          now.timeIntervalSince(modified) >= minimumAge,
                          let size = values.fileSize, size > 0,
                          let identity = values.fileResourceIdentifier else { continue }
                    files.append(JunkFile(url: url, root: base, category: root.category,
                                          bytes: Int64(size), modified: modified,
                                          fileIdentifier: String(describing: identity)))
                } catch {
                    warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return ScanResult(files: files.sorted { $0.bytes > $1.bytes }, warnings: warnings)
    }

    /// Re-check paths and metadata immediately before the caller moves a file to Trash.
    public static func validate(_ file: JunkFile, now: Date = Date()) throws {
        let base = file.root.standardizedFileURL
        var url = URL(fileURLWithPath: file.url.path).standardizedFileURL
        url.removeAllCachedResourceValues()
        guard url.path.hasPrefix(base.path + "/"),
              base.resolvingSymlinksInPath().path == base.path,
              url.resolvingSymlinksInPath().path == url.path else { throw CleanerError.outsideRoot }
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CleanerError.notRegular }
        guard values.contentModificationDate == file.modified,
              Int64(values.fileSize ?? -1) == file.bytes,
              values.fileResourceIdentifier.map({ String(describing: $0) }) == file.fileIdentifier,
              now.timeIntervalSince(file.modified) >= minimumAge else { throw CleanerError.changed }
    }
}
