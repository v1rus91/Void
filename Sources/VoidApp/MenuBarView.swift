import SwiftUI
import ServiceManagement

struct MenuBarLabel: View {
    @Environment(SystemMonitor.self) private var s
    @AppStorage("menuText") private var mode = "disk"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "smallcircle.filled.circle")
            switch mode {
            case "disk": Text(Fmt.bytes(s.diskFree))
            case "cpu": Text(Fmt.percent(s.cpu))
            case "ram": Text(Fmt.percent(Double(s.memUsed) / Double(max(s.memTotal, 1))))
            case "net": Text("↓" + Fmt.speed(s.netIn))
            default: EmptyView()
            }
        }
        .monospacedDigit()
        .task { await s.run() }
    }
}

struct MenuBarView: View {
    @Environment(SystemMonitor.self) private var s
    @Environment(Cleaner.self) private var cleaner
    @Environment(Router.self) private var router
    @Environment(Optimizer.self) private var optimizer
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("totalFreed") private var totalFreed = 0
    @State private var result: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "smallcircle.filled.circle").font(.title2)
                    .foregroundStyle(LinearGradient(colors: [.pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Void").font(.title3.bold())
                Spacer()
                Text(s.hostName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            // Disk
            let used = Double(s.diskUsed) / Double(max(s.diskTotal, 1))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Macintosh HD", systemImage: "internaldrive.fill").font(.callout.weight(.medium))
                    Spacer()
                    Text(T("вільно ", "free ") + Fmt.bytes(s.diskFree)).font(.callout.monospacedDigit())
                }
                SizeBar(fraction: used, tint: used > 0.9 ? .red : .blue)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            // Live tiles
            GlassEffectContainer(spacing: 8) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        tile(T("Процесор", "CPU"), Fmt.percent(s.cpu), s.cpuHistory, .blue)
                        tile(T("Пам'ять", "Memory"), Fmt.percent(Double(s.memUsed) / Double(max(s.memTotal, 1))), s.memHistory, .purple)
                    }
                    GridRow {
                        tile("↓ " + T("Мережа", "Network"), Fmt.speed(s.netIn), normalized(s.netInHistory, s.netOutHistory).0, .cyan)
                        if let b = s.battery {
                            tile(T("Батарея", "Battery"), "\(b)%" + (s.charging ? " ⚡︎" : ""), nil, .green, bar: Double(b) / 100)
                        } else {
                            tile("GPU", s.gpu.map(Fmt.percent) ?? "—", s.gpuHistory, .green)
                        }
                    }
                }
            }

            // Memory hogs
            if !s.topApps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("Найбільше пам'яті", "Top memory")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(s.topApps.prefix(4)) { a in AppMemRow(app: a) }
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }

            if let result {
                Label(result, systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.callout)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        working = true
                        let f = await cleaner.quickClean()
                        s.refreshDisk()
                        working = false
                        withAnimation { result = T("Звільнено ", "Freed ") + Fmt.bytes(f) }
                    }
                } label: {
                    HStack {
                        if working { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
                        Text(T("Швидке очищення", "Quick clean"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(.pink)
                .disabled(working || cleaner.busy)

                Button {
                    Task {
                        if let a = optimizer.actions.first(where: { $0.id == "ram" }) { await optimizer.run(a) }
                    }
                } label: {
                    Image(systemName: "memorychip")
                }
                .buttonStyle(.glass)
                .help(T("Звільнити пам'ять", "Free up memory"))
            }
            .controlSize(.large)

            HStack {
                Button(T("Відкрити Void", "Open Void")) {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                if totalFreed > 0 {
                    Text(T("всього ", "total ") + Fmt.bytes(Int64(totalFreed))).font(.caption).foregroundStyle(.secondary)
                }
                Button { openSettings(); NSApp.activate() } label: { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help(T("Вийти", "Quit"))
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func tile(_ title: String, _ value: String, _ history: [Double]?, _ tint: Color, bar: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
            if let history {
                Sparkline(values: Array(history.suffix(30)), tint: tint).frame(height: 22)
            } else {
                SizeBar(fraction: bar, tint: bar < 0.2 ? .red : tint).frame(height: 22)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("lang") private var lang = "system"
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("menuText") private var menuText = "disk"
    @AppStorage("lowDiskAlert") private var lowDiskAlert = true
    @AppStorage("lowDiskGB") private var lowDiskGB = 20
    @AppStorage("totalFreed") private var totalFreed = 0
    @AppStorage("cleanCount") private var cleanCount = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section(T("Загальні", "General")) {
                Picker(T("Мова", "Language"), selection: $lang) {
                    Text(T("Як у системі", "System")).tag("system")
                    Text("Українська").tag("uk")
                    Text("English").tag("en")
                }
                Toggle(T("Запускати під час входу", "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
            Section(T("Рядок меню", "Menu bar")) {
                Toggle(T("Показувати значок у рядку меню", "Show icon in the menu bar"), isOn: $showMenuBar)
                Picker(T("Поруч зі значком", "Next to the icon"), selection: $menuText) {
                    Text(T("Нічого", "Nothing")).tag("none")
                    Text(T("Вільне місце", "Free space")).tag("disk")
                    Text(T("Процесор", "CPU")).tag("cpu")
                    Text(T("Пам'ять", "Memory")).tag("ram")
                    Text(T("Швидкість мережі", "Network speed")).tag("net")
                }
                .disabled(!showMenuBar)
            }
            Section(T("Сповіщення", "Notifications")) {
                Toggle(T("Попереджати, коли мало місця", "Warn when disk space is low"), isOn: $lowDiskAlert)
                Stepper(value: $lowDiskGB, in: 5...200, step: 5) {
                    Text(T("Поріг: \(lowDiskGB) ГБ", "Threshold: \(lowDiskGB) GB"))
                }
                .disabled(!lowDiskAlert)
            }
            Section(T("Статистика", "Statistics")) {
                LabeledContent(T("Звільнено за весь час", "Freed all time"), value: Fmt.bytes(Int64(totalFreed)))
                LabeledContent(T("Очищень", "Cleanups"), value: "\(cleanCount)")
                Button(T("Скинути статистику", "Reset statistics")) { totalFreed = 0; cleanCount = 0 }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
