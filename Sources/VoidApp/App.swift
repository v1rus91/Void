import SwiftUI
import UserNotifications

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case overview, monitor, clean, analyze, large, duplicates, uninstall, startup, optimize
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: T("Огляд", "Overview")
        case .monitor: T("Монітор", "Monitor")
        case .clean: T("Очищення", "Cleanup")
        case .analyze: T("Аналіз диска", "Disk Analyzer")
        case .large: T("Великі файли", "Large Files")
        case .duplicates: T("Дублікати", "Duplicates")
        case .uninstall: T("Програми", "Applications")
        case .startup: T("Автозапуск", "Startup Items")
        case .optimize: T("Оптимізація", "Optimization")
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .monitor: "waveform.path.ecg"
        case .clean: "sparkles"
        case .analyze: "chart.pie.fill"
        case .large: "doc.on.doc.fill"
        case .duplicates: "square.on.square.fill"
        case .uninstall: "square.grid.2x2.fill"
        case .startup: "power.circle.fill"
        case .optimize: "bolt.fill"
        }
    }
    var tint: Color {
        switch self {
        case .overview: .blue
        case .monitor: .red
        case .clean: .pink
        case .analyze: .purple
        case .large: .orange
        case .duplicates: .mint
        case .uninstall: .teal
        case .startup: .yellow
        case .optimize: .green
        }
    }

    static let sections: [(LS, [Pane])] = [
        (LS("Стан", "Status"), [.overview, .monitor]),
        (LS("Місце", "Storage"), [.clean, .analyze, .large, .duplicates]),
        (LS("Система", "System"), [.uninstall, .startup, .optimize]),
    ]
}

@Observable @MainActor
final class Router {
    var pane: Pane? = UserDefaults.standard.string(forKey: "pane").flatMap(Pane.init(rawValue:)) ?? .overview
}

@main
struct VoidApp: App {
    @State private var router = Router()
    @State private var system = SystemMonitor()
    @State private var cleaner = Cleaner()
    @State private var analyzer = Analyzer()
    @State private var large = LargeFiles()
    @State private var duplicates = Duplicates()
    @State private var uninstaller = Uninstaller()
    @State private var startup = StartupItems()
    @State private var optimizer = Optimizer()
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("lang") private var lang = "system"

    init() {
        if UserDefaults.standard.object(forKey: "lowDiskAlert") as? Bool ?? true {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    var body: some Scene {
        Window("Void", id: "main") {
            RootView()
                .environment(router)
                .environment(system)
                .environment(cleaner)
                .environment(analyzer)
                .environment(large)
                .environment(duplicates)
                .environment(uninstaller)
                .environment(startup)
                .environment(optimizer)
                .frame(minWidth: 1000, minHeight: 680)
                .id(lang)
                .task { await system.run() }
        }
        .defaultSize(width: 1160, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(T("Очищення", "Cleanup")) {
                Button(T("Сканувати", "Scan")) {
                    router.pane = .clean
                    Task { await cleaner.scan() }
                }
                .keyboardShortcut("r")
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environment(router)
                .environment(system)
                .environment(cleaner)
                .environment(optimizer)
                .id(lang)
        } label: {
            MenuBarLabel().environment(system)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().id(lang)
        }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.pane) {
                ForEach(Pane.sections, id: \.0.en) { title, panes in
                    Section(title.s) {
                        ForEach(panes) { p in
                            Label {
                                Text(p.title)
                            } icon: {
                                Image(systemName: p.symbol).foregroundStyle(p.tint)
                            }
                            .tag(p)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarDisk().padding(12) }
        } detail: {
            ZStack {
                Backdrop(tint: (router.pane ?? .overview).tint)
                Group {
                    switch router.pane ?? .overview {
                    case .overview: OverviewView()
                    case .monitor: MonitorView()
                    case .clean: CleanView()
                    case .analyze: AnalyzerView()
                    case .large: LargeFilesView()
                    case .duplicates: DuplicatesView()
                    case .uninstall: UninstallView()
                    case .startup: StartupView()
                    case .optimize: OptimizeView()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .id(router.pane)
            }
            .animation(.smooth(duration: 0.3), value: router.pane)
        }
    }
}

struct SidebarDisk: View {
    @Environment(SystemMonitor.self) private var system
    @AppStorage("totalFreed") private var totalFreed = 0

    var body: some View {
        let used = Double(system.diskUsed) / Double(max(system.diskTotal, 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Spacer()
            }
            SizeBar(fraction: used, tint: used > 0.9 ? .red : used > 0.75 ? .orange : .blue)
            Text(T("Вільно \(Fmt.bytes(system.diskFree)) з \(Fmt.bytes(system.diskTotal))",
                   "\(Fmt.bytes(system.diskFree)) free of \(Fmt.bytes(system.diskTotal))"))
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            if totalFreed > 0 {
                Label(T("Звільнено Void: ", "Freed by Void: ") + Fmt.bytes(Int64(totalFreed)), systemImage: "leaf.fill")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
