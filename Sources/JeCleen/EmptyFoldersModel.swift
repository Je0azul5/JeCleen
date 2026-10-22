import AppKit
import CleanCore
import SwiftUI

@MainActor @Observable
final class EmptyFoldersModel {
    var root = FileManager.default.homeDirectoryForCurrentUser
    var result: EmptyFolderResult?
    var folders: [EmptyFolder] = []
    var selected: Set<String> = []
    var search = ""
    var progress = EmptyFolderProgress()
    var scanning = false
    var cleaning = false
    var cancelling = false
    var completedMoves = 0
    var totalMoves = 0
    var warnings: [String] = []
    var issueCount = 0
    var message: String?
    var confirmCleanup = false
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    var busy: Bool { scanning || cleaning }
    var visibleFolders: [EmptyFolder] {
        folders.filter { search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Buscar carpetas vacías"
        panel.prompt = "Analizar carpeta"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.scan(url)
        }
    }

    func scan(_ url: URL? = nil) {
        guard !busy else { return }
        root = (url ?? root).standardizedFileURL
        selected = []
        folders = []
        warnings = []
        issueCount = 0
        result = nil
        progress = EmptyFolderProgress()
        scanning = true
        cancelling = false
        operationID = UUID()
        let id = operationID
        task = Task {
            let worker = Task.detached(priority: .utility) { [root] in
                EmptyFolderCleaner.scan(root: root) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.operationID == id, self.scanning else { return }
                        self.progress = progress
                    }
                }
            }
            let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            result = value
            folders = value.folders
            progress = value.progress
            warnings = value.warnings
            issueCount = value.issueCount
            scanning = false
            cancelling = false
        }
    }

    func cancel() { cancelling = true; task?.cancel() }

    func clean() {
        let candidates = folders.filter { selected.contains($0.id) }
        guard !busy, !candidates.isEmpty else { return }
        cleaning = true
        cancelling = false
        completedMoves = 0
        totalMoves = candidates.count
        task = Task {
            let worker = Task.detached(priority: .utility) { [weak self] in
                var moved: Set<String> = []
                var failures: [String] = []
                var failureCount = 0
                var reviewed = 0
                for folder in candidates {
                    if Task.isCancelled { break }
                    do {
                        try EmptyFolderCleaner.validate(folder)
                        try FileManager.default.trashItem(at: folder.url, resultingItemURL: nil)
                        moved.insert(folder.id)
                    } catch {
                        failureCount += 1
                        if failures.count < 100 { failures.append("\(folder.url.path): \(error.localizedDescription)") }
                    }
                    reviewed += 1
                    if reviewed % 10 == 0 || reviewed == candidates.count {
                        let count = reviewed
                        await MainActor.run { [weak self] in self?.completedMoves = count }
                    }
                }
                return (moved, failures, failureCount, Task.isCancelled)
            }
            let (moved, failures, count, cancelled) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            folders.removeAll { moved.contains($0.id) }
            selected.subtract(moved)
            warnings.append(contentsOf: failures.prefix(max(0, 100 - warnings.count)))
            issueCount += count
            cleaning = false
            cancelling = false
            message = "Se movieron \(moved.count) carpetas vacías a la Papelera. Puedes recuperarlas desde Finder."
                + (count > 0 ? " Se omitieron \(count) carpetas; revisa los avisos." : "")
                + (cancelled ? " La operación fue cancelada; las restantes no se movieron." : "")
                + " Vuelve a analizar para encontrar carpetas que hayan quedado vacías."
        }
    }
}
