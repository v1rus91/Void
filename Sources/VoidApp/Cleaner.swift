import SwiftUI
import Observation

enum CleanMode: Sendable {
    case purge      // remove the contents of a folder (or the file itself)
    case remove     // remove the item itself
    case trash      // move to Trash (recoverable)
}

struct CleanItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    var size: Int64
    var selected = true
}

struct CleanDefinition: Sendable {
    let id: String
    let title: LS
    let subtitle: LS
    let symbol: String
    let tint: Color
    let mode: CleanMode
    let collect: @Sendable () -> [(URL, String)]
}

struct CleanCategory: Identifiable {
    let def: CleanDefinition
    var items: [CleanItem]
    var expanded = false
    let order: Int

    var id: String { def.id }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { $0 + ($1.selected ? $1.size : 0) } }
    var state: CheckState {
        let n = items.filter(\.selected).count
        return n == 0 ? .off : n == items.count ? .on : .mixed
    }
}

// MARK: - Catalog of what we know how to clean

enum CleanCatalog {
    static let lib = home.sub("Library")

    /// Folders in ~/Library/Caches owned by the dedicated categories below.
    static let claimed: Set<String> = [
        "Homebrew", "Yarn", "pip", "pnpm", "go-build", "CocoaPods", "org.swift.swiftpm", "ms-playwright",
        "node-gyp", "com.apple.dt.Xcode", "JetBrains", "typescript", "deno", "bun",
        "com.apple.Safari", "Google", "Firefox", "Mozilla", "BraveSoftware", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "Microsoft Edge", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]
    /// System caches that are unsafe or pointless to remove.
    static let protected: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.akd", "com.apple.HomeKit", "FamilyCircle",
        "com.apple.ScreenTimeAgent", "com.apple.Safari.SafeBrowsing", "com.apple.containermanagerd",
        "PassKit", "com.apple.ap.adprivacyd", "com.apple.findmy.fmipcore", "com.apple.nsurlsessiond",
        "com.v1rus.void",
    ]

    static func existing(_ list: [(String, String)], base: URL = home) -> [(URL, String)] {
        list.map { (base.sub($0.0), $0.1) }.filter { FS.exists($0.0) }
    }

    static func chromiumCaches(_ root: String, _ label: String) -> [(URL, String)] {
        let r = lib.sub("Application Support").sub(root)
        guard FS.exists(r) else { return [] }
        var out: [(URL, String)] = []
        for p in FS.children(r) where p.lastPathComponent == "Default" || p.lastPathComponent.hasPrefix("Profile ") {
            for c in ["Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "Service Worker/CacheStorage"] {
                let u = p.sub(c)
                if FS.exists(u) { out.append((u, "\(label) · \(p.lastPathComponent) · \(c)")) }
            }
        }
        for c in ["ShaderCache", "GrShaderCache", "component_crx_cache"] {
            let u = r.sub(c)
            if FS.exists(u) { out.append((u, "\(label) · \(c)")) }
        }
        return out
    }

    static let all: [CleanDefinition] = [
        CleanDefinition(id: "caches", title: LS("Кеші програм", "App caches"), subtitle: LS("Тимчасові дані, які програми створять знову", "Temporary data apps will recreate"),
                        symbol: "shippingbox.fill", tint: .blue, mode: .purge) {
            FS.children(lib.sub("Caches"))
                .filter { !claimed.contains($0.lastPathComponent) && !protected.contains($0.lastPathComponent) }
                .map { ($0, FS.prettyName($0)) }
        },
        CleanDefinition(id: "browsers", title: LS("Кеші браузерів", "Browser caches"), subtitle: LS("Safari, Chrome, Arc, Brave, Firefox, Edge", "Safari, Chrome, Arc, Brave, Firefox, Edge"),
                        symbol: "globe", tint: .cyan, mode: .purge) {
            existing([
                ("Library/Caches/com.apple.Safari", "Safari"),
                ("Library/Caches/Google/Chrome", "Chrome"),
                ("Library/Caches/company.thebrowser.Browser", "Arc"),
                ("Library/Caches/BraveSoftware", "Brave"),
                ("Library/Caches/Firefox", "Firefox"),
                ("Library/Caches/Mozilla", "Firefox"),
                ("Library/Caches/com.microsoft.edgemac", "Edge"),
                ("Library/Caches/Microsoft Edge", "Edge"),
                ("Library/Caches/com.operasoftware.Opera", "Opera"),
                ("Library/Caches/com.vivaldi.Vivaldi", "Vivaldi"),
            ])
            + chromiumCaches("Google/Chrome", "Chrome")
            + chromiumCaches("BraveSoftware/Brave-Browser", "Brave")
            + chromiumCaches("Arc/User Data", "Arc")
            + chromiumCaches("Microsoft Edge", "Edge")
        },
        CleanDefinition(id: "dev", title: LS("Сміття розробника", "Developer junk"), subtitle: LS("Xcode, симулятори, npm, Homebrew, pip, Gradle…", "Xcode, simulators, npm, Homebrew, pip, Gradle…"),
                        symbol: "hammer.fill", tint: .indigo, mode: .purge) {
            existing([
                ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
                ("Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport"),
                ("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS DeviceSupport"),
                ("Library/Developer/Xcode/macOS DeviceSupport", "macOS DeviceSupport"),
                ("Library/Developer/Xcode/iOS Device Logs", "iOS Device Logs"),
                ("Library/Developer/CoreSimulator/Caches", T("Кеші симуляторів", "Simulator caches")),
                ("Library/Caches/com.apple.dt.Xcode", T("Кеш Xcode", "Xcode cache")),
                ("Library/Caches/Homebrew", "Homebrew"),
                ("Library/Caches/Yarn", "Yarn"),
                ("Library/Caches/pip", "pip"),
                ("Library/Caches/pnpm", "pnpm"),
                ("Library/Caches/go-build", "Go build"),
                ("Library/Caches/CocoaPods", "CocoaPods"),
                ("Library/Caches/org.swift.swiftpm", "Swift PM"),
                ("Library/Caches/ms-playwright", T("Playwright браузери", "Playwright browsers")),
                ("Library/Caches/node-gyp", "node-gyp"),
                ("Library/Caches/JetBrains", "JetBrains"),
                ("Library/Caches/typescript", "TypeScript"),
                ("Library/Caches/deno", "Deno"),
                (".npm/_cacache", "npm"),
                (".bun/install/cache", "Bun"),
                (".gradle/caches", "Gradle"),
                (".cargo/registry/cache", "Cargo"),
                (".m2/repository", "Maven"),
                (".cache/pre-commit", "pre-commit"),
            ])
        },
        CleanDefinition(id: "logs", title: LS("Журнали та звіти", "Logs & reports"), subtitle: LS("Логи програм і звіти про збої", "App logs and crash reports"),
                        symbol: "doc.text.fill", tint: .orange, mode: .purge) {
            FS.children(lib.sub("Logs")).map { ($0, FS.prettyName($0)) }
        },
        CleanDefinition(id: "temp", title: LS("Тимчасові файли", "Temporary files"), subtitle: LS("Старші за 3 дні з системної тимчасової теки", "Older than 3 days in the system temp folder"),
                        symbol: "clock.arrow.circlepath", tint: .teal, mode: .remove) {
            let cutoff = Date.now.addingTimeInterval(-3 * 86400)
            return FS.children(URL(fileURLWithPath: NSTemporaryDirectory()))
                .filter { (FS.modified($0) ?? .now) < cutoff }
                .map { ($0, $0.lastPathComponent) }
        },
        CleanDefinition(id: "installers", title: LS("Інсталятори", "Installers"), subtitle: LS("DMG, PKG і XIP у Завантаженнях — у Кошик", "DMG, PKG and XIP in Downloads — to Trash"),
                        symbol: "arrow.down.app.fill", tint: .green, mode: .trash) {
            FS.children(home.sub("Downloads"))
                .filter { ["dmg", "pkg", "mpkg", "xip"].contains($0.pathExtension.lowercased()) }
                .map { ($0, $0.lastPathComponent) }
        },
        CleanDefinition(id: "ios", title: LS("Оновлення iOS та Пошта", "iOS updates & Mail"), subtitle: LS("Прошивки iPhone/iPad і завантажені вкладення", "iPhone/iPad firmware and downloaded attachments"),
                        symbol: "iphone.gen3", tint: .pink, mode: .purge) {
            existing([
                ("Library/iTunes/iPhone Software Updates", T("Оновлення iPhone", "iPhone updates")),
                ("Library/iTunes/iPad Software Updates", T("Оновлення iPad", "iPad updates")),
            ]) + (Cleaner.fullDiskAccess() ? existing([
                ("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", T("Вкладення Пошти", "Mail attachments")),
            ]) : [])
        },
        CleanDefinition(id: "trash", title: LS("Кошик", "Trash"), subtitle: LS("Остаточне видалення вмісту Кошика", "Permanently empty the Trash"),
                        symbol: "trash.fill", tint: .red, mode: .remove) {
            FS.children(home.sub(".Trash")).map { ($0, $0.lastPathComponent) }
        },
    ]
}

// MARK: - Model

@Observable @MainActor
final class Cleaner {
    enum Phase: Equatable { case idle, scanning, ready, cleaning, done(freed: Int64, failed: Int) }

    var phase: Phase = .idle
    var categories: [CleanCategory] = []
    var progress: Double = 0
    var currentStep = ""
    var lastScan: Date?
    var lastFreed: Int64?
    var busy: Bool { phase == .scanning || phase == .cleaning }
    var hasFullDiskAccess = Cleaner.fullDiskAccess()

    var total: Int64 { categories.reduce(0) { $0 + $1.total } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.items.filter(\.selected).count } }

    nonisolated static func fullDiskAccess() -> Bool {
        let probes = ["Library/Safari", "Library/Mail", "Library/Messages"].map { home.sub($0) }.filter(FS.exists)
        guard !probes.isEmpty else { return true }
        return probes.contains { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil }
    }

    func scan() async {
        guard phase != .scanning, phase != .cleaning else { return }
        hasFullDiskAccess = Cleaner.fullDiskAccess()
        withAnimation(.smooth) { phase = .scanning; categories = []; progress = 0 }
        let defs = CleanCatalog.all
        currentStep = T("Пошук…", "Searching…")
        var finished = 0
        await withTaskGroup(of: (Int, [CleanItem]).self) { g in
            for (i, d) in defs.enumerated() {
                g.addTask {
                    let pairs = d.collect()
                    let sizes = await DiskSizer.sizes(pairs.map(\.0))
                    let items = pairs.compactMap { u, n -> CleanItem? in
                        let s = sizes[u] ?? 0
                        return s > 0 ? CleanItem(url: u, name: n, size: s, selected: d.id != "trash") : nil
                    }
                    return (i, items.sorted { $0.size > $1.size })
                }
            }
            for await (i, items) in g {
                finished += 1
                currentStep = defs[i].title.s
                withAnimation(.spring(duration: 0.5)) {
                    progress = Double(finished) / Double(defs.count)
                    if !items.isEmpty {
                        let cat = CleanCategory(def: defs[i], items: items, order: i)
                        let idx = categories.firstIndex { $0.order > i } ?? categories.count
                        categories.insert(cat, at: idx)
                    }
                }
            }
        }
        lastScan = .now
        withAnimation(.smooth) { phase = .ready }
    }

    func clean() async {
        let work = categories.flatMap { c in c.items.filter(\.selected).map { ($0, c.def.mode) } }
        guard !work.isEmpty else { return }
        withAnimation(.smooth) { phase = .cleaning; progress = 0 }
        var freed: Int64 = 0
        var failed = 0
        for (n, (item, mode)) in work.enumerated() {
            currentStep = item.name
            let f = await Task.detached(priority: .userInitiated) {
                Cleaner.remove(item.url, mode: mode, expected: item.size)
            }.value
            freed += f
            if f == 0 { failed += 1 }
            progress = Double(n + 1) / Double(work.count)
        }
        Stats.add(freed)
        lastFreed = freed
        for i in categories.indices { categories[i].items.removeAll(where: \.selected) }
        categories.removeAll { $0.items.isEmpty }
        withAnimation(.spring(duration: 0.6)) { phase = .done(freed: freed, failed: failed) }
    }

    /// Scan + clean only the always-safe categories. Used from the menu bar.
    func quickClean() async -> Int64 {
        guard !busy else { return 0 }
        await scan()
        let safe: Set<String> = ["caches", "logs", "temp"]
        for i in categories.indices {
            let on = safe.contains(categories[i].id)
            for j in categories[i].items.indices { categories[i].items[j].selected = on }
        }
        guard selectedSize > 0 else { phase = .ready; return 0 }
        await clean()
        if case .done(let f, _) = phase { return f }
        return 0
    }

    func reset() { withAnimation(.smooth) { phase = categories.isEmpty ? .idle : .ready } }

    nonisolated static func remove(_ url: URL, mode: CleanMode, expected: Int64) -> Int64 {
        let fm = FileManager.default
        switch mode {
        case .remove:
            return (try? fm.removeItem(at: url)) != nil ? expected : 0
        case .trash:
            return (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil ? expected : 0
        case .purge:
            guard FS.exists(url) else { return expected }
            guard FS.isDirectory(url) else { return (try? fm.removeItem(at: url)) != nil ? expected : 0 }
            for c in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: c)
            }
            return max(0, expected - DiskSizer.size(of: url))
        }
    }

    // MARK: selection

    func toggle(category id: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        let on = categories[i].state != .on
        for j in categories[i].items.indices { categories[i].items[j].selected = on }
    }

    func toggle(item: UUID, in id: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }),
              let j = categories[i].items.firstIndex(where: { $0.id == item }) else { return }
        categories[i].items[j].selected.toggle()
    }

    func toggleExpanded(_ id: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { categories[i].expanded.toggle() }
    }

    func selectAll(_ on: Bool) {
        for i in categories.indices {
            for j in categories[i].items.indices { categories[i].items[j].selected = on }
        }
    }
}
