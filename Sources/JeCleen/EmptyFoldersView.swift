import AppKit
import CleanCore
import SwiftUI

struct EmptyFoldersView: View {
    @Bindable var model: EmptyFoldersModel
    @State private var showWarnings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Deja atrás las carpetas vacías.").font(.system(size: 30, weight: .semibold)).tracking(-1)
                Text("Busca carpetas sin contenido, revísalas y elige cuáles mover a la Papelera.")
                    .font(.system(size: 13)).foregroundStyle(muted)
            }
            HStack(spacing: 12) {
                Button { model.scan() } label: { Label("Buscar carpetas vacías", systemImage: "magnifyingglass") }
                    .buttonStyle(PrimaryButton()).disabled(model.busy)
                Button("Elegir carpeta…", systemImage: "folder") { model.chooseFolder() }
                    .buttonStyle(.bordered).disabled(model.busy)
                Spacer()
                if model.busy {
                    Button(model.cancelling ? "Cancelando…" : "Cancelar") { model.cancel() }
                        .buttonStyle(.borderless).foregroundStyle(accent).disabled(model.cancelling)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(accent)
                Text(model.root.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.root]) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.borderless).help("Mostrar carpeta en Finder")
            }.padding(15).background(surface, in: RoundedRectangle(cornerRadius: 10))
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(accent)
                Text("Una carpeta con archivos ocultos, incluso .DS_Store, no está vacía. Se omiten carpetas ocultas, Library, System, paquetes de apps y otros volúmenes. La carpeta elegida y las carpetas personales principales se conservan. Quitar carpetas vacías ayuda a ordenar; apenas libera espacio.")
                    .foregroundStyle(muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }.font(.system(size: 11)).padding(15).background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            if model.busy {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(model.cleaning ? "Moviendo carpetas a la Papelera…" : "Buscando carpetas sin contenido…")
                            .font(.system(size: 14, weight: .medium))
                    }
                    if model.cleaning {
                        ProgressView(value: Double(model.completedMoves), total: Double(max(1, model.totalMoves)))
                        Text("\(model.completedMoves) de \(model.totalMoves) revisadas").font(.system(size: 11)).foregroundStyle(muted)
                    } else {
                        Text("\(model.progress.reviewed.formatted()) carpetas revisadas · \(model.progress.found.formatted()) vacías")
                            .font(.system(size: 12)).foregroundStyle(muted)
                        Text(model.progress.currentPath).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle)
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if let result = model.result, !model.scanning {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(model.folders.count.formatted()) carpetas vacías").font(.system(size: 22, weight: .semibold))
                        Text(result.cancelled ? "Análisis cancelado · resultados parciales" : "\(result.progress.reviewed.formatted()) carpetas revisadas")
                            .font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer()
                    if model.issueCount > 0 {
                        Button("\(model.issueCount) avisos", systemImage: "exclamationmark.triangle") { showWarnings = true }
                            .buttonStyle(.borderless).foregroundStyle(.orange)
                    }
                }
                if model.issueCount > 0 {
                    Text("Algunas rutas no se pudieron revisar. El análisis es parcial; consulta los avisos.")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
                HStack {
                    Button(!model.visibleFolders.isEmpty && model.visibleFolders.allSatisfy { model.selected.contains($0.id) } ? "Desmarcar resultados" : "Seleccionar resultados") {
                        let ids = Set(model.visibleFolders.map(\.id))
                        if ids.isSubset(of: model.selected) { model.selected.subtract(ids) }
                        else { model.selected.formUnion(ids) }
                    }.buttonStyle(.borderless).foregroundStyle(accent).disabled(model.visibleFolders.isEmpty || model.busy)
                    Spacer()
                    TextField("Buscar por nombre o ruta", text: $model.search).textFieldStyle(.roundedBorder)
                        .frame(width: 250).disabled(model.busy)
                }.font(.system(size: 11))
                if model.visibleFolders.isEmpty {
                    emptyState(model.folders.isEmpty ? "No hay carpetas vacías que mostrar" : "No hay resultados para esta búsqueda")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.visibleFolders) { folder in
                                HStack(spacing: 12) {
                                    Toggle("Seleccionar \(folder.url.path)", isOn: Binding(get: { model.selected.contains(folder.id) }, set: { value in
                                        if value { model.selected.insert(folder.id) } else { model.selected.remove(folder.id) }
                                    })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                                    Image(systemName: "folder").font(.system(size: 21)).foregroundStyle(accent)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(folder.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(folder.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(muted)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text("Vacía").font(.system(size: 10)).foregroundStyle(muted)
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) } label: { Image(systemName: "arrow.up.right") }
                                        .buttonStyle(.borderless).foregroundStyle(muted).help("Mostrar en Finder")
                                }.padding(15).help(folder.url.path)
                                    .overlay(alignment: .bottom) { Divider().opacity(0.15).padding(.leading, 45) }
                            }
                        }
                    }.frame(height: 300).background(surface, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Text("\(model.selected.count) seleccionadas").font(.system(size: 12)).foregroundStyle(muted)
                    Spacer()
                    Button { model.confirmCleanup = true } label: { Label("Mover a la Papelera", systemImage: "trash") }
                        .buttonStyle(PrimaryButton()).disabled(model.busy || model.selected.isEmpty)
                }
            } else if !model.scanning {
                emptyState("Elige una carpeta e inicia el análisis")
            }
        }
        .confirmationDialog("¿Mover \(model.selected.count) carpetas vacías a la Papelera?", isPresented: $model.confirmCleanup, titleVisibility: .visible) {
            Button("Mover a la Papelera", role: .destructive) { model.clean() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se comprobará que cada carpeta siga vacía. Las carpetas que hayan cambiado se omitirán. Puedes recuperar las carpetas movidas desde Finder. Cierra las apps que puedan estar usando estas rutas.")
        }
        .alert("Carpetas vacías", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Entendido") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .sheet(isPresented: $showWarnings) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Avisos de carpetas vacías").font(.title2.bold())
                Text("Se muestran hasta 100 avisos de acceso o de carpetas que cambiaron.").foregroundStyle(muted)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.system(size: 11)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Cerrar") { showWarnings = false }.buttonStyle(PrimaryButton()).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(28).frame(width: 680, height: 440)
        }
    }

    private func emptyState(_ title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.minus").font(.system(size: 34, weight: .light)).foregroundStyle(accent)
            Text(title).font(.system(size: 15, weight: .medium))
            Text("Nada se selecciona ni se elimina automáticamente.").font(.system(size: 12)).foregroundStyle(muted)
        }.padding(.vertical, 40).frame(maxWidth: .infinity).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
