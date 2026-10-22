import AppKit
import CleanCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, storage, cleanup, emptyFolders, memory, processes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Vista general"
        case .storage: "Almacenamiento"
        case .cleanup: "Limpieza"
        case .emptyFolders: "Carpetas vacías"
        case .memory: "Memoria"
        case .processes: "Procesos"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .storage: "internaldrive"
        case .cleanup: "sparkles"
        case .emptyFolders: "folder.badge.minus"
        case .memory: "memorychip"
        case .processes: "waveform.path.ecg"
        }
    }
}

@MainActor @Observable
final class AppModel {
    var page = Page.overview
    var storage = StorageModel()
    var emptyFolders = EmptyFoldersModel()
    var memoryGroups: [MemoryGroup] = []
    var snapshot = SystemSnapshot()
    var files: [JunkFile] = []
    var selected: Set<String> = []
    var warnings: [String] = []
    var scanning = false
    var cleaning = false
    var didScan = false
    var lastScan: Date?
    var lastUpdate: Date?
    var search = ""
    var processSearch = ""
    var category: JunkCategory?
    var message: String?
    var confirmCleanup = false
    var appToClose: ProcessRow?
    var scanTask: Task<Void, Never>?
    var monitorTask: Task<Void, Never>?

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    var selectedFiles: [JunkFile] { files.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.bytes } }
    var visibleFiles: [JunkFile] {
        files.filter { (category == nil || $0.category == category) && (search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search)) }
    }
    var visibleProcesses: [ProcessRow] {
        snapshot.processes.filter { processSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(processSearch) || String($0.id).contains(processSearch) }
    }
    var closableApps: [ProcessRow] { snapshot.processes.filter { canClose($0) } }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let value = await Task.detached(priority: .utility) { SystemSnapshot.read() }.value
                guard let self else { return }
                self.snapshot = value
                self.memoryGroups = MemoryGroup.group(value.processes)
                self.lastUpdate = Date()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func scan() {
        guard !scanning, !cleaning else { return }
        scanning = true
        didScan = false
        lastScan = nil
        selected.removeAll()
        files = []
        warnings = []
        scanTask = Task {
            let worker = Task.detached(priority: .utility) { Cleaner.scan(roots: ScanRoot.userRoots()) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { scanning = false; return }
            files = result.files
            warnings = result.warnings
            lastScan = Date()
            didScan = true
            scanning = false
        }
    }

    func cancelScan() { scanTask?.cancel() }

    func clean() {
        let candidates = selectedFiles
        guard !candidates.isEmpty, !cleaning else { return }
        cleaning = true
        Task {
            var removed: Set<String> = []
            var failures: [String] = []
            var bytes: Int64 = 0
            // Trash operations are local and sequential. Revalidate each file before touching it.
            for file in candidates {
                do {
                    try Cleaner.validate(file)
                    try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                    removed.insert(file.id)
                    bytes += file.bytes
                } catch { failures.append("\(file.url.lastPathComponent): \(error.localizedDescription)") }
                await Task.yield()
            }
            files.removeAll { removed.contains($0.id) }
            selected.subtract(removed)
            warnings.append(contentsOf: failures)
            cleaning = false
            message = "Se movieron \(removed.count) archivos (\(byteString(bytes))) a la Papelera."
                + (failures.isEmpty ? " Puedes recuperarlos desde Finder. El espacio se recupera al vaciar la Papelera." : " No se pudieron mover \(failures.count) archivos; revisa los avisos.")
        }
    }

    func canClose(_ row: ProcessRow) -> Bool {
        guard row.id != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: row.id),
              app.activationPolicy == .regular,
              app.bundleIdentifier != "com.apple.finder" else { return false }
        return !app.isTerminated
    }

    func close(_ row: ProcessRow) {
        guard canClose(row), let app = NSRunningApplication(processIdentifier: row.id) else {
            message = "La aplicación ya no está disponible para cerrar."
            return
        }
        let requested = app.terminate()
        message = requested
            ? "Se solicitó cerrar \(row.name). Si tiene documentos abiertos, revisa su diálogo para guardarlos. El consumo se actualizará en unos segundos."
            : "\(row.name) no aceptó la solicitud de cierre. Puedes revisarla en Monitor de Actividad."
    }
}
