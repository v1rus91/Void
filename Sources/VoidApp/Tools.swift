import SwiftUI
import AppKit
import Observation

// MARK: - Disk analyzer

@Observable @MainActor
final class Analyzer {
    struct Entry: Identifiable {
        let id: URL
        let isDir: Bool
        var size: Int64?
        var url: URL { id }
        var name: String { FileManager.default.displayName(atPath: id.path) }
    }

    var stack: [URL] = [home]
    var entries: [Entry] = []
    var loading = false
    private var cache: [URL: [Entry]] = [:]
    private var task: Task<Void, Never>?

    var current: URL { stack.last ?? home }
    var total: Int64 { entries.reduce(0) { $0 + ($1.size ?? 0) } }
    var maxSize: Int64 { entries.compactMap(\.size).max() ?? 1 }

    func setRoot(_ u: URL) { stack = [u]; load() }
    func open(_ u: URL) { stack.append(u); load() }
    func go(to i: Int) { stack = Array(stack.prefix(i + 1)); load() }

    func load(force: Bool = false) {
        task?.cancel()
        let dir = current
        if !force, let c = cache[dir] { entries = c; loading = false; return }
        let kids = FS.children(dir).map { u in
            Entry(id: u, isDir: FS.isDirectory(u) && !FS.isPackage(u), size: nil)
        }
        entries = kids
        loading = true
        task = Task {
            await withTaskGroup(of: (URL, Int64).self) { g in
                for e in kids { g.addTask { (e.id, DiskSizer.size(of: e.id)) } }
                for await (u, s) in g {
                    guard !Task.isCancelled, current == dir else { continue }
                    if let i = entries.firstIndex(where: { $0.id == u }) { entries[i].size = s }
                }
            }
            guard !Task.isCancelled, current == dir else { return }
            withAnimation(.snappy) { entries.sort { ($0.size ?? 0) > ($1.size ?? 0) } }
            cache[dir] = entries
            loading = false
        }
    }

    func trash(_ e: Entry) {
        guard (try? FileManager.default.trashItem(at: e.id, resultingItemURL: nil)) != nil else { NSSound.beep(); return }
        Stats.add(e.size ?? 0)
        withAnimation { entries.removeAll { $0.id == e.id } }
        cache.removeAll()
        cache[current] = entries
    }
}

// MARK: - Large files

@Observable @MainActor
final class LargeFiles {
    struct File: Identifiable {
        let id: URL
        let size: Int64
        let modified: Date?
        var selected = false
    }

    var files: [File] = []
    var scanning = false
    var scanned = 0
    var threshold: Int64 = 500 * 1_000_000
    var includeLibrary = false
    var hasScanned = false
    private var task: Task<Void, Never>?

    var selectedSize: Int64 { files.reduce(0) { $0 + ($1.selected ? $1.size : 0) } }
    var selectedCount: Int { files.filter(\.selected).count }

    func scan() {
        task?.cancel()
        scanning = true; hasScanned = true; scanned = 0
        withAnimation { files = [] }
        let th = threshold, lib = includeLibrary
        task = Task {
            let found = await Task.detached(priority: .userInitiated) {
                LargeFiles.walk(threshold: th, includeLibrary: lib) { n in
                    Task { @MainActor in self.scanned = n }
                }
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(.spring) { files = found.sorted { $0.size > $1.size } }
            scanning = false
        }
    }

    func stop() { task?.cancel(); scanning = false }

    nonisolated static func walk(threshold: Int64, includeLibrary: Bool, progress: @escaping (Int) -> Void) -> [File] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys,
                                                     options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] }
        var skip: Set<String> = [home.sub(".Trash").path]
        if !includeLibrary { skip.insert(home.sub("Library").path) }
        var out: [File] = []
        var n = 0
        while let u = e.nextObject() as? URL {
            n += 1
            if n % 4000 == 0 {
                if Task.isCancelled { break }
                progress(n)
            }
            if skip.contains(u.path) { e.skipDescendants(); continue }
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let s = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            if s >= threshold { out.append(File(id: u, size: s, modified: v.contentModificationDate)) }
        }
        progress(n)
        return out
    }

    func toggle(_ id: URL) {
        if let i = files.firstIndex(where: { $0.id == id }) { files[i].selected.toggle() }
    }

    func trashSelected() {
        var removed: Set<URL> = []
        for f in files where f.selected {
            if (try? FileManager.default.trashItem(at: f.id, resultingItemURL: nil)) != nil { removed.insert(f.id) }
        }
        Stats.add(files.filter { removed.contains($0.id) }.reduce(0) { $0 + $1.size })
        withAnimation(.spring) { files.removeAll { removed.contains($0.id) } }
    }
}

// MARK: - Uninstaller

@Observable @MainActor
final class Uninstaller {
    struct AppInfo: Identifiable, Hashable {
        let id: URL
        let name: String
        let bundleID: String
        let version: String
        var size: Int64?
        var lastUsed: Date?
    }

    struct Leftover: Identifiable {
        let id: URL
        let label: String
        var size: Int64
        var selected = true
    }

    enum Sort: String, CaseIterable {
        case name, size, used
        var title: String {
            switch self {
            case .name: T("Назва", "Name")
            case .size: T("Розмір", "Size")
            case .used: T("Використання", "Last used")
            }
        }
    }

    var apps: [AppInfo] = []
    var loading = false
    var selectedID: URL?
    var leftovers: [Leftover] = []
    var findingLeftovers = false
    var search = ""
    var sort: Sort = .size
    var working = false
    var message: String?

    var selected: AppInfo? { apps.first { $0.id == selectedID } }
    var leftoversSize: Int64 { leftovers.reduce(0) { $0 + ($1.selected ? $1.size : 0) } }

    var visible: [AppInfo] {
        let f = search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .name: return f.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .size: return f.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .used: return f.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    func load() async {
        guard apps.isEmpty, !loading else { return }
        loading = true
        let found = await Task.detached { Uninstaller.discover() }.value
        apps = found
        loading = false
        let sizes = await DiskSizer.sizes(found.map(\.id))
        withAnimation(.snappy) {
            for i in apps.indices { apps[i].size = sizes[apps[i].id] }
        }
    }

    nonisolated static func discover() -> [AppInfo] {
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"), home.sub("Applications")]
        var urls: [URL] = []
        for r in roots {
            for c in FS.children(r) {
                if c.pathExtension == "app" { urls.append(c) }
                else if FS.isDirectory(c), c.lastPathComponent != "Utilities" {
                    urls += FS.children(c).filter { $0.pathExtension == "app" }
                }
            }
        }
        return urls.compactMap { u in
            guard let b = Bundle(url: u), let id = b.bundleIdentifier,
                  !id.hasPrefix("com.apple."), id != Bundle.main.bundleIdentifier else { return nil }
            let info = b.infoDictionary ?? [:]
            let ver = info["CFBundleShortVersionString"] as? String ?? ""
            var used: Date?
            if let md = MDItemCreateWithURL(nil, u as CFURL) {
                used = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
            }
            return AppInfo(id: u, name: u.deletingPathExtension().lastPathComponent, bundleID: id, version: ver, lastUsed: used)
        }
    }

    func select(_ id: URL?) {
        selectedID = id
        message = nil
        leftovers = []
        guard let app = selected else { return }
        findingLeftovers = true
        Task {
            let list = await Task.detached { Uninstaller.leftovers(for: app) }.value
            guard selectedID == app.id else { return }
            withAnimation(.snappy) { leftovers = list; findingLeftovers = false }
        }
    }

    nonisolated static func leftovers(for app: AppInfo) -> [Leftover] {
        let L = home.sub("Library")
        let b = app.bundleID, n = app.name
        var cands: [(URL, String)] = [(app.id, T("Програма", "Application"))]
        func add(_ rel: String, _ label: String) { cands.append((L.sub(rel), label)) }
        add("Application Support/\(b)", T("Дані програми", "App data"))
        add("Caches/\(b)", T("Кеш", "Cache"))
        add("Containers/\(b)", T("Контейнер", "Container"))
        add("Application Scripts/\(b)", T("Скрипти", "Scripts"))
        add("Saved Application State/\(b).savedState", T("Збережений стан", "Saved state"))
        add("HTTPStorages/\(b)", T("HTTP-сховище", "HTTP storage"))
        add("HTTPStorages/\(b).binarycookies", T("Cookies", "Cookies"))
        add("Cookies/\(b).binarycookies", T("Cookies", "Cookies"))
        add("WebKit/\(b)", T("WebKit-дані", "WebKit data"))
        add("Logs/\(b)", T("Журнали", "Logs"))
        if n.count >= 3 {
            add("Application Support/\(n)", T("Дані програми", "App data"))
            add("Caches/\(n)", T("Кеш", "Cache"))
            add("Logs/\(n)", T("Журнали", "Logs"))
        }
        for p in FS.children(L.sub("Preferences")) where p.lastPathComponent.hasPrefix(b) {
            cands.append((p, T("Налаштування", "Preferences")))
        }
        for p in FS.children(L.sub("LaunchAgents")) where p.lastPathComponent.hasPrefix(b) {
            cands.append((p, T("Агент запуску", "Launch agent")))
        }
        for p in FS.children(L.sub("Group Containers")) where p.lastPathComponent.hasSuffix(b) {
            cands.append((p, T("Груповий контейнер", "Group container")))
        }
        var seen: Set<String> = []
        return cands.compactMap { u, label in
            guard FS.exists(u), seen.insert(u.path).inserted else { return nil }
            return Leftover(id: u, label: label, size: DiskSizer.size(of: u))
        }
    }

    func toggle(_ id: URL) {
        if let i = leftovers.firstIndex(where: { $0.id == id }) { leftovers[i].selected.toggle() }
    }

    func uninstall() async {
        guard let app = selected else { return }
        working = true
        for r in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            r.terminate()
        }
        try? await Task.sleep(for: .seconds(1))
        var freed: Int64 = 0, failed = 0
        for l in leftovers where l.selected {
            var ok = (try? FileManager.default.trashItem(at: l.id, resultingItemURL: nil)) != nil
            if !ok, l.id == app.id { ok = await Shell.adminTrash(l.id) }
            if ok { freed += l.size } else { failed += 1 }
        }
        working = false
        let appGone = !FS.exists(app.id)
        Stats.add(freed)
        message = T("Переміщено в Кошик: ", "Moved to Trash: ") + Fmt.bytes(freed) + (failed > 0 ? T(" · не вдалося: ", " · failed: ") + "\(failed)" : "")
        if appGone {
            withAnimation(.snappy) {
                apps.removeAll { $0.id == app.id }
                leftovers = []
            }
        } else {
            select(app.id)
        }
    }
}

// MARK: - Optimizer

struct OptAction: Identifiable {
    let id: String
    let title: LS
    let detail: LS
    let symbol: String
    let tint: Color
    let admin: Bool
    let command: String
}

@Observable @MainActor
final class Optimizer {
    enum Status: Equatable { case idle, running, ok(String), fail(String) }

    var status: [String: Status] = [:]

    let actions: [OptAction] = [
        OptAction(id: "ram", title: LS("Звільнити пам'ять", "Free up memory"), detail: LS("Скидає неактивну пам'ять і дисковий кеш (purge).", "Flushes inactive memory and disk cache (purge)."),
                  symbol: "memorychip.fill", tint: .purple, admin: true, command: "/usr/sbin/purge"),
        OptAction(id: "dns", title: LS("Скинути DNS-кеш", "Flush DNS cache"), detail: LS("Допомагає, коли сайти не відкриваються після зміни мережі.", "Helps when sites won’t load after a network change."),
                  symbol: "network", tint: .blue, admin: true, command: "dscacheutil -flushcache; killall -HUP mDNSResponder"),
        OptAction(id: "snap", title: LS("Локальні знімки Time Machine", "Local Time Machine snapshots"), detail: LS("Видаляє локальні знімки, що займають «очищуване» місце.", "Removes local snapshots that hold “purgeable” space."),
                  symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: .green, admin: true,
                  command: "tmutil thinlocalsnapshots / 999999999999 4"),
        OptAction(id: "ql", title: LS("Кеш Quick Look", "Quick Look cache"), detail: LS("Перебудовує мініатюри та попередній перегляд файлів.", "Rebuilds thumbnails and file previews."),
                  symbol: "eye.fill", tint: .teal, admin: false, command: "qlmanage -r cache; qlmanage -r"),
        OptAction(id: "ls", title: LS("Меню «Відкрити за допомогою»", "“Open With” menu"), detail: LS("Перебудовує базу Launch Services — прибирає дублікати програм.", "Rebuilds Launch Services — removes duplicate apps."),
                  symbol: "list.bullet.rectangle.fill", tint: .orange, admin: false,
                  command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user"),
        OptAction(id: "ui", title: LS("Перезапустити Dock і Finder", "Restart Dock & Finder"), detail: LS("Лікує зависання Dock, Finder та рядка меню.", "Fixes a frozen Dock, Finder or menu bar."),
                  symbol: "dock.rectangle", tint: .indigo, admin: false, command: "killall Dock; killall Finder; killall SystemUIServer; true"),
        OptAction(id: "spot", title: LS("Переіндексувати Spotlight", "Reindex Spotlight"), detail: LS("Для випадків, коли пошук нічого не знаходить. Займе час.", "When search finds nothing. Takes a while."),
                  symbol: "magnifyingglass", tint: .pink, admin: true, command: "mdutil -E /"),
    ]

    func run(_ a: OptAction) async {
        status[a.id] = .running
        let r = a.admin ? await Shell.runAdmin(a.command) : await Shell.run(a.command)
        withAnimation(.snappy) {
            if r.code == 0 {
                status[a.id] = .ok(T("Готово · ", "Done · ") + Date.now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Loc.locale)))
            } else {
                let msg = r.out.contains("-128") ? T("Скасовано", "Cancelled") : (r.out.split(separator: "\n").last.map(String.init) ?? T("Помилка", "Error"))
                status[a.id] = .fail(msg)
            }
        }
    }
}
