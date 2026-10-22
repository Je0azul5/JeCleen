import AppKit
import CleanCore
import SwiftUI

struct StorageView: View {
    @Bindable var model: StorageModel
    @State private var showWarnings = false
    private let colors: [Color] = [accent, .init(red: 0.57, green: 0.72, blue: 0.97), .init(red: 0.93, green: 0.69, blue: 0.43), .init(red: 0.74, green: 0.60, blue: 0.91), .init(red: 0.37, green: 0.76, blue: 0.72), .pink, .yellow, .gray]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cada carpeta cuenta.").font(.system(size: 32, weight: .semibold)).tracking(-1)
                Text("Descubre dónde se va el espacio. Entra en una carpeta para explorar su contenido.")
                    .font(.system(size: 13)).foregroundStyle(muted)
            }
            HStack(spacing: 10) {
                Button { model.scan() } label: { Label(model.result == nil ? "Analizar carpeta" : "Volver a analizar", systemImage: "magnifyingglass") }
                    .buttonStyle(PrimaryButton()).disabled(model.scanning)
                Button("Elegir carpeta…", systemImage: "folder") { model.chooseFolder() }
                    .buttonStyle(.bordered).disabled(model.scanning)
                Spacer()
                if model.scanning {
                    Button(model.cancelling ? "Cancelando…" : "Cancelar") { model.cancel() }
                        .disabled(model.cancelling).buttonStyle(.borderless).foregroundStyle(accent)
                }
            }
            HStack(spacing: 10) {
                shortcut("Mi usuario", icon: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                shortcut("Aplicaciones", icon: "app.dashed", url: URL(fileURLWithPath: "/Applications"))
                shortcut("Disco de datos", icon: "internaldrive", url: URL(fileURLWithPath: "/System/Volumes/Data"))
                Spacer()
            }.disabled(model.scanning)
            HStack(spacing: 10) {
                Button { model.back() } label: { Image(systemName: "arrow.left") }
                    .disabled(!model.canGoBack).help("Volver a la carpeta anterior")
                Image(systemName: "folder.fill").foregroundStyle(accent)
                Text(model.root.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 5)
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.root]) } label: { Image(systemName: "arrow.up.right") }
                    .help("Mostrar carpeta en Finder")
            }.buttonStyle(.borderless).padding(14).background(surface, in: RoundedRectangle(cornerRadius: 10))

            if model.scanning { progress }
            else if let result = model.result {
                summary(result)
                if result.cancelled || result.issueCount > 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(result.cancelled ? "Análisis cancelado. Los tamaños son parciales." : "Análisis parcial: algunas rutas no se pudieron medir o pertenecen a otro volumen.")
                        Spacer()
                        if result.issueCount > 0 {
                            Button("\(result.issueCount) avisos") { showWarnings = true }.foregroundStyle(accent)
                        }
                    }.font(.system(size: 11)).padding(14).background(.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                distribution(result)
                folderList
                largestFiles
                Text("Solo se leen metadatos; no se descargan contenidos de iCloud. Los enlaces simbólicos y otros volúmenes se omiten. Los tamaños se suman por ruta: enlaces duros y clones APFS pueden compartir bloques, por lo que el total no equivale a espacio recuperable. No incluye snapshots ni metadatos del sistema de archivos.")
                    .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 36, weight: .light)).foregroundStyle(accent)
                    Text("¿Qué está ocupando tu disco?").font(.system(size: 17, weight: .medium))
                    Text("Analiza tu usuario o elige cualquier carpeta para ver su distribución.")
                        .font(.system(size: 12)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 55).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .sheet(isPresented: $showWarnings) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rutas sin medir").font(.title2.bold())
                Text("Se muestran hasta 100 avisos. Las carpetas protegidas por macOS pueden quedar fuera del total.").foregroundStyle(muted)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array((model.result?.warnings ?? []).enumerated()), id: \.offset) { _, text in
                            Text(text).font(.system(size: 11)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Cerrar") { showWarnings = false }.buttonStyle(PrimaryButton()).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(28).frame(width: 680, height: 450)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Midiendo el contenido…").font(.system(size: 16, weight: .medium))
                Spacer()
                Text(byteString(model.progress.allocatedBytes)).monospacedDigit().foregroundStyle(accent)
            }
            Text("\(model.progress.files.formatted()) archivos · \(model.progress.folders.formatted()) carpetas")
                .font(.system(size: 12)).foregroundStyle(muted)
            Text(model.progress.currentPath).font(.system(size: 10)).lineLimit(1).truncationMode(.middle).foregroundStyle(muted)
            Text("Puedes seguir usando las demás secciones mientras se analiza.").font(.system(size: 11)).foregroundStyle(muted)
        }.padding(24).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func summary(_ result: StorageResult) -> some View {
        HStack(spacing: 14) {
            stat("Medido en disco", value: byteString(result.allocatedBytes), icon: "internaldrive")
            stat("Tamaño lógico", value: byteString(result.logicalBytes), icon: "doc")
            stat("Archivos revisados", value: result.progress.files.formatted(), icon: "doc.on.doc")
        }
    }

    private func stat(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(muted)
            Text(value).font(.system(size: 25, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func distribution(_ result: StorageResult) -> some View {
        let sorted = result.entries.sorted { $0.bytes(model.mode) > $1.bytes(model.mode) }
        let leaders = Array(sorted.filter { $0.bytes(model.mode) > 0 }.prefix(7))
        let remainder = max(0, model.totalBytes - leaders.reduce(0) { $0 + $1.bytes(model.mode) })
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("DISTRIBUCIÓN DE LA CARPETA").font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Picker("Medida de almacenamiento", selection: $model.mode) {
                    ForEach(StorageSizeMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            if model.totalBytes > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(leaders.enumerated()), id: \.element.id) { index, entry in
                            Rectangle().fill(colors[index]).frame(width: geometry.size.width * Double(entry.bytes(model.mode)) / Double(model.totalBytes))
                                .help("\(entry.url.lastPathComponent): \(byteString(entry.bytes(model.mode)))")
                        }
                        if remainder > 0 {
                            Rectangle().fill(colors[7]).frame(width: geometry.size.width * Double(remainder) / Double(model.totalBytes))
                                .help("Resto: \(byteString(remainder))")
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 7))
                }.frame(height: 34)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 13) {
                    ForEach(Array(leaders.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 8) {
                            Circle().fill(colors[index]).frame(width: 7, height: 7)
                            Text(entry.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(percentage(entry.bytes(model.mode))).foregroundStyle(muted).monospacedDigit()
                        }.font(.system(size: 11))
                    }
                    if remainder > 0 {
                        HStack(spacing: 8) {
                            Circle().fill(colors[7]).frame(width: 7, height: 7)
                            Text("Resto")
                            Spacer()
                            Text(percentage(remainder)).foregroundStyle(muted)
                        }.font(.system(size: 11))
                    }
                }
            } else { Text("No se encontró espacio medible con esta medida.").font(.system(size: 12)).foregroundStyle(muted) }
            Text(model.mode == .allocated ? "Bloques asignados a los archivos según macOS." : "Tamaño declarado de los archivos, incluidos contenidos que podrían estar solo en iCloud.")
                .font(.system(size: 10)).foregroundStyle(muted)
        }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var folderList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CARPETAS Y ARCHIVOS").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted)
                Spacer()
                Toggle("Solo carpetas", isOn: $model.foldersOnly).toggleStyle(.checkbox).font(.system(size: 11))
                TextField("Buscar nombre", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            Text("\(model.entries.count) elementos · ordenados por \(model.mode.rawValue.lowercased())")
                .font(.system(size: 10)).foregroundStyle(muted)
            if model.entries.isEmpty {
                Text("No hay elementos que coincidan.").font(.system(size: 12)).foregroundStyle(muted).padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { ForEach(model.entries) { entry in storageRow(entry) } }
                }.frame(height: 330).background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var largestFiles: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LOS 20 ARCHIVOS MÁS GRANDES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted)
            Text("Dentro de toda la carpeta analizada y sus subcarpetas · \(model.mode.rawValue.lowercased())")
                .font(.system(size: 11)).foregroundStyle(muted)
            if model.largestFiles.isEmpty {
                Text("No se encontraron archivos regulares.").font(.system(size: 12)).foregroundStyle(muted)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.largestFiles) { entry in storageRow(entry, showPath: true) }
                }.background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func storageRow(_ entry: StorageEntry, showPath: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isLink ? "link" : entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 20)).foregroundStyle(entry.isDirectory ? accent : muted).frame(width: 27)
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    if entry.isDirectory && !entry.isLink { model.scan(entry.url) }
                    else { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                } label: {
                    Text(entry.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.plain).disabled(model.scanning)
                if showPath {
                    Text(entry.url.deletingLastPathComponent().path).lineLimit(1).truncationMode(.middle)
                        .font(.system(size: 10)).foregroundStyle(muted)
                } else {
                    Text(entry.isLink ? "Enlace omitido" : "\(entry.fileCount.formatted()) \(entry.fileCount == 1 ? "archivo" : "archivos")\(entry.issueCount > 0 ? " · parcial" : "")")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
            }
            Spacer(minLength: 12)
            if !showPath {
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.04))
                    Capsule().fill(accent.opacity(0.7)).frame(width: geo.size.width * (model.totalBytes > 0 ? Double(entry.bytes(model.mode)) / Double(model.totalBytes) : 0))
                }.frame(width: 75, height: 4)
                Text(percentage(entry.bytes(model.mode))).font(.system(size: 10)).foregroundStyle(muted).frame(width: 42, alignment: .trailing)
            }
            Text(byteString(entry.bytes(model.mode))).font(.system(size: 12)).monospacedDigit().frame(width: 90, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).foregroundStyle(muted).help("Mostrar en Finder")
            if entry.isDirectory && !entry.isLink {
                Button { model.scan(entry.url) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).foregroundStyle(accent).help("Analizar esta carpeta").disabled(model.scanning)
            } else { Color.clear.frame(width: 10, height: 10) }
        }.padding(15).help(entry.url.path)
            .overlay(alignment: .bottom) { Divider().opacity(0.15).padding(.leading, 52) }
    }

    private func shortcut(_ title: String, icon: String, url: URL) -> some View {
        Button(title, systemImage: icon) { model.scan(url) }.font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(muted)
    }
    private func percentage(_ bytes: Int64) -> String {
        String(format: "%.1f%%", model.totalBytes > 0 ? Double(bytes) / Double(model.totalBytes) * 100 : 0)
    }
}
