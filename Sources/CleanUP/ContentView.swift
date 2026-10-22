import AppKit
import CleanCore
import SwiftUI

private let accent = Color(red: 0.73, green: 0.94, blue: 0.43)
private let canvasColor = Color(red: 0.065, green: 0.078, blue: 0.078)
private let surface = Color(red: 0.10, green: 0.12, blue: 0.12)
private let muted = Color(red: 0.59, green: 0.64, blue: 0.62)

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showWarnings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.page {
                        case .overview: overview
                        case .cleanup: cleanup
                        case .memory: memory
                        case .processes: processes
                        }
                        if let error = model.snapshot.error { notice(error, symbol: "exclamationmark.triangle") }
                    }.padding(32)
                }
                HStack(spacing: 7) {
                    Circle().fill(model.lastUpdate == nil ? muted : accent).frame(width: 5, height: 5)
                    Text(model.lastUpdate == nil ? "Conectando con tu Mac…" : "Datos locales · actualización cada 5 segundos")
                    Spacer()
                    Text("CleanUP  /  1.0").monospaced()
                }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 32).padding(.vertical, 13)
            }
        }
        .background(canvasColor)
        .tint(accent)
        .confirmationDialog("¿Mover \(model.selectedFiles.count) archivos a la Papelera?", isPresented: $model.confirmCleanup, titleVisibility: .visible) {
            Button("Mover \(byteString(model.selectedBytes)) a la Papelera", role: .destructive) { model.clean() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Cierra las aplicaciones relacionadas antes de limpiar sus cachés. Podrán regenerarse al abrirlas. Puedes recuperar los archivos desde la Papelera.")
        }
        .alert("Cerrar aplicación", isPresented: Binding(get: { model.appToClose != nil }, set: { if !$0 { model.appToClose = nil } })) {
            Button("Cancelar", role: .cancel) { model.appToClose = nil }
            Button("Solicitar cierre") {
                if let app = model.appToClose { model.close(app) }
                model.appToClose = nil
            }
        } message: {
            Text("Se solicitará cerrar \(model.appToClose?.name ?? "la aplicación"). Guarda tu trabajo antes de continuar. La aplicación puede pedirte guardar los documentos abiertos.")
        }
        .alert("CleanUP", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Entendido") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .sheet(isPresented: $showWarnings) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Avisos del análisis").font(.title2.bold())
                Text("El análisis solo incluye archivos que macOS permite leer. No es necesario conceder acceso total al disco.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.system(size: 12)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Cerrar") { showWarnings = false }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(28).frame(width: 650, height: 440)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(accent)
                Text("CleanUP").font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-1)
            }.padding(.top, 52).padding(.bottom, 44).padding(.horizontal, 25)
            Text("TU ESPACIO, EN ORDEN").font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(muted).padding(.horizontal, 25).padding(.bottom, 16)
            ForEach(Page.allCases) { page in
                Button {
                    model.page = page
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.icon).font(.system(size: 16)).frame(width: 21)
                        Text(page.title).font(.system(size: 13, weight: model.page == page ? .semibold : .medium))
                        Spacer()
                        if model.page == page { Circle().fill(accent).frame(width: 5, height: 5) }
                    }
                    .foregroundStyle(model.page == page ? accent : muted)
                    .padding(.horizontal, 15).padding(.vertical, 14)
                    .background(model.page == page ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "lock.shield").font(.system(size: 22)).foregroundStyle(accent)
                Text("Tu Mac. Tus decisiones.").font(.system(size: 12, weight: .semibold))
                Text("Revisa primero. Limpia después.\nTodo se queda en tu Mac.")
                    .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).padding(16)
            Divider().overlay(.white.opacity(0.04)).padding(.horizontal, 20)
            Label(Host.current().localizedName ?? "Mi Mac", systemImage: "laptopcomputer")
                .font(.system(size: 11)).foregroundStyle(muted).lineLimit(1).padding(23)
        }.frame(width: 222).background(Color(red: 0.08, green: 0.095, blue: 0.095))
            .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.055)).frame(width: 1) }
    }

    private var header: some View {
        HStack {
            Text("Mi Mac").foregroundStyle(muted)
            Text("/").foregroundStyle(muted.opacity(0.4)).padding(.horizontal, 5)
            Text(model.page.title)
            Spacer()
            Label("Solo en este dispositivo", systemImage: "lock").font(.system(size: 11)).foregroundStyle(muted)
        }.font(.system(size: 12)).padding(.horizontal, 32).padding(.top, 27).padding(.bottom, 22)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MENOS RUIDO. MÁS ESPACIO.").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(accent)
                    Text("Dale un respiro\na tu Mac.").font(.system(size: 42, weight: .semibold)).tracking(-1.5).lineSpacing(-2)
                    Text("Un lugar para revisar, limpiar y entender tu equipo.")
                        .font(.system(size: 13)).foregroundStyle(muted).padding(.top, 2)
                }
                Spacer()
                Text(Date.now, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 11)).foregroundStyle(muted).padding(.top, 5)
            }
            HStack(spacing: 28) {
                ZStack {
                    Circle().stroke(accent.opacity(0.09), lineWidth: 13)
                    Circle().trim(from: 0, to: model.scanning ? 0.7 : 1)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: model.scanning ? "magnifyingglass" : "sparkles")
                        .font(.system(size: 42, weight: .light)).foregroundStyle(accent)
                }.frame(width: 116, height: 116).padding(10)
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.scanning ? "Buscando espacio…" : model.didScan ? "Tu análisis está listo" : "Un buen comienzo")
                        .font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                    Text(model.didScan ? "\(byteString(model.totalBytes)) en \(model.files.count) archivos para revisar." : "Encuentra cachés y registros antiguos.\nTú eliges qué se va y qué se queda.")
                        .font(.system(size: 13)).foregroundStyle(muted).lineSpacing(5)
                    if model.scanning { ProgressView().controlSize(.small) }
                    else {
                        Button {
                            model.page = .cleanup
                            if !model.didScan { model.scan() }
                        } label: {
                            Label(model.didScan ? "Revisar archivos" : "Analizar mi Mac", systemImage: "arrow.right")
                        }.buttonStyle(PrimaryButton()).padding(.top, 9)
                    }
                }
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [accent.opacity(0.08), surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.16), lineWidth: 1))
            HStack(spacing: 16) {
                metricCard("Almacenamiento", symbol: "internaldrive", value: model.snapshot.diskTotal == 0 ? "—" : byteString(model.snapshot.diskFree), subtitle: "disponibles", fraction: model.snapshot.diskTotal == 0 ? 0 : 1 - Double(model.snapshot.diskFree) / Double(model.snapshot.diskTotal), color: accent)
                metricCard("Memoria en uso", symbol: "memorychip", value: model.lastUpdate == nil ? "—" : byteString(Int64(model.snapshot.memoryUsed)), subtitle: "de \(byteString(Int64(model.snapshot.memoryTotal))) · estimación", fraction: model.snapshot.memoryFraction, color: Color(red: 0.64, green: 0.74, blue: 0.99))
                metricCard("Procesos", symbol: "waveform.path.ecg", value: model.lastUpdate == nil ? "—" : "\(model.snapshot.processes.count)", subtitle: "activos en el sistema", fraction: nil, color: .orange)
            }
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Pequeños hábitos, un Mac más ligero.").font(.system(size: 14, weight: .medium))
                    Text("Cierra las apps que ya no usas para dejar memoria disponible.").font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                Button("Ver memoria", systemImage: "arrow.up.right") { model.page = .memory }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12))
            }.padding(.vertical, 8)
        }
    }

    private var cleanup: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeading("Un poco de limpieza.", detail: "Revisa archivos sin cambios durante al menos 7 días en ~/Library/Caches y ~/Library/Logs.")
            HStack(spacing: 12) {
                Button { model.scan() } label: { Label(model.didScan ? "Volver a analizar" : "Analizar archivos", systemImage: "magnifyingglass") }
                    .buttonStyle(PrimaryButton()).disabled(model.scanning || model.cleaning)
                if model.scanning {
                    ProgressView().controlSize(.small)
                    Text("Analizando archivos…").font(.system(size: 12)).foregroundStyle(muted)
                    Button("Cancelar") { model.cancelScan() }.buttonStyle(.borderless)
                } else if let date = model.lastScan {
                    Text("Último análisis: \(date.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundStyle(muted)
                }
                Spacer()
                if !model.warnings.isEmpty { Button("\(model.warnings.count) avisos", systemImage: "exclamationmark.triangle") { showWarnings = true }.buttonStyle(.borderless).foregroundStyle(.orange) }
            }
            HStack(spacing: 14) {
                ForEach(JunkCategory.allCases) { category in
                    let items = model.files.filter { $0.category == category }
                    Button { model.category = model.category == category ? nil : category } label: {
                        HStack(spacing: 14) {
                            Image(systemName: category.symbol).font(.system(size: 24)).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(category.title).font(.system(size: 13, weight: .medium))
                                Text("\(items.count) archivos · \(byteString(items.reduce(0) { $0 + $1.bytes }))").font(.system(size: 11)).foregroundStyle(muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.category == category ? accent : .clear))
                    }.buttonStyle(.plain)
                }
            }
            notice("Las cachés pueden contener datos útiles y volver a crecer. Revisa las rutas y cierra las apps relacionadas antes de limpiar.", symbol: "info.circle")
            HStack {
                Text("ARCHIVOS PARA REVISAR").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(muted)
                Spacer()
                TextField("Buscar por nombre o ruta", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 230)
            }
            if model.visibleFiles.isEmpty {
                emptyState(model.scanning ? "Revisando tu biblioteca…" : model.didScan ? "No hay archivos que mostrar" : "Todo empieza con un análisis", detail: model.didScan ? "Prueba otro filtro o revisa los avisos de acceso." : "No se borra nada durante el análisis.", icon: "sparkle.magnifyingglass")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button(model.visibleFiles.allSatisfy { model.selected.contains($0.id) } ? "Desmarcar visibles" : "Seleccionar visibles") {
                            let ids = Set(model.visibleFiles.map(\.id))
                            if ids.isSubset(of: model.selected) { model.selected.subtract(ids) } else { model.selected.formUnion(ids) }
                        }.buttonStyle(.borderless).foregroundStyle(accent)
                        Spacer()
                        Text("\(model.visibleFiles.count) archivos").foregroundStyle(muted)
                    }.font(.system(size: 11)).padding(14)
                    Divider().opacity(0.3)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.visibleFiles) { file in fileRow(file) }
                        }
                    }.frame(height: 275)
                }.background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(byteString(model.selectedBytes)).font(.system(size: 25, weight: .semibold)).monospacedDigit()
                    Text("\(model.selected.count) archivos seleccionados").font(.system(size: 11)).foregroundStyle(muted)
                }
                Spacer()
                if model.cleaning { ProgressView().controlSize(.small) }
                Button { model.confirmCleanup = true } label: { Label(model.cleaning ? "Moviendo archivos…" : "Mover a la Papelera", systemImage: "trash") }
                    .buttonStyle(PrimaryButton()).disabled(model.selected.isEmpty || model.cleaning || model.scanning)
            }
        }.disabled(model.cleaning)
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeading("Más aire para tus apps.", detail: "Mira cómo se usa la memoria y cierra las aplicaciones que ya no necesitas.")
            HStack(spacing: 25) {
                ZStack {
                    Circle().stroke(.white.opacity(0.06), lineWidth: 14)
                    Circle().trim(from: 0, to: model.snapshot.memoryFraction).stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 5) {
                        Text(model.lastUpdate == nil ? "—" : "\(Int(model.snapshot.memoryFraction * 100))%")
                            .font(.system(size: 32, weight: .semibold)).monospacedDigit()
                        Text("en uso aprox.").font(.system(size: 10)).foregroundStyle(muted)
                    }
                }.frame(width: 150, height: 150).padding(8)
                VStack(alignment: .leading, spacing: 15) {
                    memoryLine("Memoria física", value: model.snapshot.memoryTotal)
                    memoryLine("En uso · estimación", value: model.snapshot.memoryUsed)
                    memoryLine("Disponible · estimación", value: model.snapshot.memoryTotal - model.snapshot.memoryUsed)
                    memoryLine("Comprimida (incluida en uso)", value: model.snapshot.compressed)
                }.frame(maxWidth: .infinity)
            }.padding(26).background(surface, in: RoundedRectangle(cornerRadius: 16))
            notice("macOS administra la RAM automáticamente. La estimación disponible incluye páginas libres e inactivas; no mide la presión de memoria. Cerrar una app puede liberar recursos, según lo que macOS necesite.", symbol: "info.circle")
            HStack {
                Text("APLICACIONES ABIERTAS").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(muted)
                Spacer()
                Button("Monitor de Actividad", systemImage: "arrow.up.right") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }.buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(accent)
            }
            if model.closableApps.isEmpty {
                emptyState("Sin aplicaciones para cerrar", detail: "Los procesos del sistema se administran desde macOS.", icon: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.closableApps) { row in processRow(row, allowClose: true) }
                }.background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var processes: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeading("Lo que mueve tu Mac.", detail: "Procesos ordenados por uso de memoria residente. Los datos se renuevan cada 5 segundos.")
            HStack {
                Text("\(model.visibleProcesses.count) procesos").font(.system(size: 13)).foregroundStyle(muted)
                Spacer()
                TextField("Buscar proceso o PID", text: $model.processSearch).textFieldStyle(.roundedBorder).frame(width: 260)
            }
            notice("Puedes solicitar el cierre normal de tus aplicaciones. Los servicios del sistema y Finder se muestran solo para consulta. CPU puede superar el 100% cuando usa varios núcleos.", symbol: "shield.lefthalf.filled")
            VStack(spacing: 0) {
                HStack {
                    Text("PROCESO / PID")
                    Spacer()
                    Text("CPU").frame(width: 65, alignment: .trailing)
                    Text("MEMORIA").frame(width: 95, alignment: .trailing)
                    Text("ACCIÓN").frame(width: 75)
                }.font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(muted).padding(16)
                Divider().opacity(0.3)
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleProcesses) { row in processRow(row, allowClose: model.canClose(row)) }
                }
            }.background(surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fileRow(_ file: JunkFile) -> some View {
        HStack(spacing: 11) {
            Toggle("Seleccionar \(file.url.lastPathComponent)", isOn: Binding(get: { model.selected.contains(file.id) }, set: { value in
                if value { model.selected.insert(file.id) } else { model.selected.remove(file.id) }
            })).labelsHidden().toggleStyle(.checkbox)
            Image(systemName: file.category.symbol).foregroundStyle(muted).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(byteString(file.bytes)).font(.system(size: 11)).monospacedDigit().foregroundStyle(muted)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).foregroundStyle(muted).help("Mostrar en Finder")
        }.padding(.horizontal, 14).padding(.vertical, 11).help(file.url.path)
        .overlay(alignment: .bottom) { Divider().opacity(0.15).padding(.leading, 43) }
    }

    private func processRow(_ row: ProcessRow, allowClose: Bool) -> some View {
        HStack(spacing: 12) {
            if let app = NSRunningApplication(processIdentifier: row.id), let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 27, height: 27)
            } else {
                Image(systemName: "terminal").font(.system(size: 15)).foregroundStyle(muted).frame(width: 27, height: 27)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("PID \(row.id)").font(.system(size: 10)).foregroundStyle(muted)
            }
            Spacer(minLength: 10)
            Text(String(format: "%.1f%%", row.cpu)).frame(width: 65, alignment: .trailing).foregroundStyle(muted)
            Text(byteString(row.memory)).frame(width: 95, alignment: .trailing)
            if allowClose {
                Button("Cerrar") { model.appToClose = row }.buttonStyle(.bordered).controlSize(.small).frame(width: 75)
            } else { Text("Sistema").foregroundStyle(muted).font(.system(size: 10)).frame(width: 75) }
        }.font(.system(size: 11)).monospacedDigit().padding(.horizontal, 16).padding(.vertical, 12)
            .help(row.path).overlay(alignment: .bottom) { Divider().opacity(0.15).padding(.leading, 54) }
    }

    private func memoryLine(_ title: String, value: UInt64) -> some View {
        HStack {
            Text(title).foregroundStyle(muted)
            Spacer()
            Text(model.lastUpdate == nil ? "—" : byteString(Int64(value))).monospacedDigit()
        }.font(.system(size: 12))
    }

    private func metricCard(_ title: String, symbol: String, value: String, subtitle: String, fraction: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).foregroundStyle(muted)
            }.font(.system(size: 11))
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 27, weight: .medium)).tracking(-1).monospacedDigit()
                Text(subtitle).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
            }
            if let fraction {
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.05))
                    Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }.frame(height: 4)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(model.snapshot.processes.prefix(22).enumerated()), id: \.offset) { _, row in
                        RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.65))
                            .frame(height: max(2, min(14, row.cpu / 4 + 2)))
                    }
                }.frame(height: 4, alignment: .bottom).accessibilityLabel("Actividad de los procesos")
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func pageHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 32, weight: .semibold)).tracking(-1)
            Text(detail).font(.system(size: 13)).foregroundStyle(muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func notice(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(text).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }.font(.system(size: 11)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    private func emptyState(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(accent)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 44).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(canvasColor)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.35)
    }
    @Environment(\.isEnabled) private var isEnabled
}
