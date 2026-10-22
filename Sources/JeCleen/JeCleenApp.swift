import SwiftUI

@main
struct JeCleenApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1020, minHeight: 700)
                .preferredColorScheme(.dark)
                .task { model.startMonitoring() }
        }
        .defaultSize(width: 1190, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Explorar almacenamiento") { model.page = .storage }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Analizar archivos") { model.page = .cleanup; model.scan() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.scanning || model.cleaning)
            }
        }
    }
}
