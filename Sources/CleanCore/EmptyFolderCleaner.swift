import Darwin
import Foundation

public struct EmptyFolder: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let root: URL
    public let identity: String
}

public struct EmptyFolderProgress: Sendable {
    public var reviewed = 0
    public var found = 0
    public var currentPath = ""
    public init() {}
}

public struct EmptyFolderResult: Sendable {
    public let folders: [EmptyFolder]
    public let progress: EmptyFolderProgress
    public let warnings: [String]
    public let issueCount: Int
    public let cancelled: Bool
}

public enum EmptyFolderError: LocalizedError {
    case protectedPath, notDirectory, notEmpty, changed
    public var errorDescription: String? {
        switch self {
        case .protectedPath: "Esta ruta está protegida, es un enlace o está fuera de la carpeta elegida."
        case .notDirectory: "La ruta no es una carpeta normal."
        case .notEmpty: "La carpeta ya no está vacía. Vuelve a analizar."
        case .changed: "La carpeta fue reemplazada desde el análisis. Vuelve a analizar."
        }
    }
}

public enum EmptyFolderCleaner {
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileResourceIdentifierKey, .volumeIdentifierKey]

    private static func excluded(_ url: URL) -> Bool {
        let parts = url.pathComponents
        if parts.contains(where: { $0.hasPrefix(".") || $0 == "Library" || $0 == "System" }) { return true }
        let reserved = ["/bin", "/sbin", "/usr", "/dev", "/private/var", "/var", "/Network"]
        return reserved.contains { url.path == $0 || url.path.hasPrefix($0 + "/") }
    }

    private static func protectedContainer(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let containers = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"]
        return ["/", "/Users", "/Volumes", "/Applications", home.path].contains(url.path)
            || containers.contains { home.appendingPathComponent($0).path == url.path }
    }

    private static func checkRoot(_ root: URL) throws {
        guard !excluded(root), !["/", "/Users", "/Volumes"].contains(root.path),
              root.resolvingSymlinksInPath().path == root.path else { throw EmptyFolderError.protectedPath }
        let info = try root.resourceValues(forKeys: keys)
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw EmptyFolderError.notDirectory }
        var ancestor = root
        while true {
            let values = try ancestor.resourceValues(forKeys: keys)
            // Foundation may normalize system aliases such as /private/tmp to /tmp.
            // The resolved-path check above guards the scope; ancestors are checked for packages.
            guard values.isPackage != true else { throw EmptyFolderError.notDirectory }
            if ancestor.path == "/" { break }
            ancestor = ancestor.deletingLastPathComponent()
        }
    }

    /// Inspect directory entries including hidden files, without opening file contents.
    private static func isEmpty(_ url: URL) throws -> Bool {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard let directory = fdopendir(fd) else {
            let error = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }
        defer { closedir(directory) }
        errno = 0
        while let entry = readdir(directory) {
            let name = entry.pointee.d_name
            if name.0 == 46 && (name.1 == 0 || (name.1 == 46 && name.2 == 0)) { continue }
            return false
        }
        guard errno == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return true
    }

    public static func scan(root: URL, report: @Sendable (EmptyFolderProgress) -> Void = { _ in }) -> EmptyFolderResult {
        let base = root.standardizedFileURL
        var folders: [EmptyFolder] = []
        var progress = EmptyFolderProgress()
        var warnings: [String] = []
        var issues = 0
        var lastReport = Date.distantPast
        func warn(_ url: URL, _ error: String) {
            issues += 1
            if warnings.count < 100 { warnings.append("\(url.path): \(error)") }
        }
        do {
            try checkRoot(base)
            let values = try base.resourceValues(forKeys: keys)
            let volume = values.volumeIdentifier.map { String(describing: $0) }
            if let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants, .skipsHiddenFiles], errorHandler: { url, error in
                    warn(url, error.localizedDescription)
                    return !Task.isCancelled
                }) {
                for case let url as URL in enumerator {
                    if Task.isCancelled { break }
                    do {
                        let info = try url.resourceValues(forKeys: keys)
                        if excluded(url) || info.isSymbolicLink == true || info.isPackage == true {
                            enumerator.skipDescendants()
                            continue
                        }
                        guard info.isDirectory == true else { continue }
                        if info.volumeIdentifier.map({ String(describing: $0) }) != volume {
                            enumerator.skipDescendants()
                            warn(url, "Se omitió otro volumen.")
                            continue
                        }
                        progress.reviewed += 1
                        if !protectedContainer(url), try isEmpty(url), let identity = info.fileResourceIdentifier {
                            folders.append(EmptyFolder(url: url, root: base, identity: String(describing: identity)))
                            progress.found += 1
                        }
                        if Date().timeIntervalSince(lastReport) > 0.25 {
                            progress.currentPath = url.path
                            report(progress)
                            lastReport = Date()
                        }
                    } catch { warn(url, error.localizedDescription) }
                }
            } else { warn(base, "No se pudo revisar el contenido de la carpeta.") }
        } catch { warn(base, error.localizedDescription) }
        report(progress)
        return EmptyFolderResult(folders: folders.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending },
                                 progress: progress, warnings: warnings, issueCount: issues, cancelled: Task.isCancelled)
    }

    public static func validate(_ folder: EmptyFolder) throws {
        let root = folder.root.standardizedFileURL
        try checkRoot(root)
        var url = URL(fileURLWithPath: folder.url.path).standardizedFileURL
        url.removeAllCachedResourceValues()
        guard !excluded(url), !protectedContainer(url), url.path.hasPrefix(root.path + "/"),
              root.resolvingSymlinksInPath().path == root.path,
              url.resolvingSymlinksInPath().path == url.path else { throw EmptyFolderError.protectedPath }
        // A parent may have been replaced by an application package after the scan.
        var ancestor = url
        while ancestor.path != root.path {
            let info = try ancestor.resourceValues(forKeys: keys)
            guard info.isDirectory == true, info.isSymbolicLink != true, info.isPackage != true else { throw EmptyFolderError.notDirectory }
            ancestor = ancestor.deletingLastPathComponent()
        }
        let values = try url.resourceValues(forKeys: keys)
        guard values.fileResourceIdentifier.map({ String(describing: $0) }) == folder.identity else { throw EmptyFolderError.changed }
        let rootVolume = try root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard values.volumeIdentifier.map({ String(describing: $0) }) == rootVolume.map({ String(describing: $0) }) else { throw EmptyFolderError.protectedPath }
        guard try isEmpty(url) else { throw EmptyFolderError.notEmpty }
    }
}
