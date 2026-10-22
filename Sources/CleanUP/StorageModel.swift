import AppKit
import CleanCore
import SwiftUI

@MainActor @Observable
final class StorageModel {
    var root = FileManager.default.homeDirectoryForCurrentUser
    var result: StorageResult?
    var progress = StorageProgress()
    var scanning = false
    var cancelling = false
    var mode = StorageSizeMode.allocated
    var search = ""
    var foldersOnly = false
    private var scanID = UUID()
    private var task: Task<Void, Never>?
    private var history: [URL] = []

    var canGoBack: Bool { !history.isEmpty && !scanning }
    var entries: [StorageEntry] {
        (result?.entries ?? []).filter {
            (!foldersOnly || $0.isDirectory) && (search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search))
        }.sorted { $0.bytes(mode) == $1.bytes(mode) ? $0.id < $1.id : $0.bytes(mode) > $1.bytes(mode) }
    }
    var largestFiles: [StorageEntry] {
        Array((result?.largestFiles ?? []).sorted { $0.bytes(mode) > $1.bytes(mode) }.prefix(20))
    }
    var totalBytes: Int64 { mode == .allocated ? result?.allocatedBytes ?? 0 : result?.logicalBytes ?? 0 }

    func scan(_ url: URL? = nil, remember: Bool = true) {
        guard !scanning else { return }
        let nextRoot = (url ?? root).standardizedFileURL
        if remember, nextRoot.path != root.path { history.append(root) }
        root = nextRoot
        result = nil
        progress = StorageProgress()
        search = ""
        scanning = true
        cancelling = false
        let id = UUID()
        scanID = id
        task = Task {
            let worker = Task.detached(priority: .utility) { [root] in
                StorageScanner.scan(root: root) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.scanID == id, self.scanning else { return }
                        self.progress = progress
                    }
                }
            }
            let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard scanID == id else { return }
            result = value
            progress = value.progress
            scanning = false
            cancelling = false
        }
    }

    func cancel() { cancelling = true; task?.cancel() }

    func back() {
        guard !scanning, let previous = history.popLast() else { return }
        scan(previous, remember: false)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Elige una carpeta para analizar"
        panel.prompt = "Analizar carpeta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.scan(url)
        }
    }
}
