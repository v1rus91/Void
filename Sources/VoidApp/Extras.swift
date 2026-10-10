import SwiftUI
import AppKit
import CryptoKit
import Observation

// MARK: - Startup items (launchd agents & daemons)

@Observable @MainActor
final class StartupItems {
    enum Scope: Int, CaseIterable {
        case user, global, daemon
        var title: String {
            switch self {
            case .user: T("Агенти користувача", "User agents")
            case .global: T("Агенти для всіх", "Global agents")
            case .daemon: T("Системні служби", "System daemons")
            }
        }
        var dir: URL {
            switch self {
            case .user: home.sub("Library/LaunchAgents")
            case .global: URL(fileURLWithPath: "/Library/LaunchAgents")
            case .daemon: URL(fileURLWithPath: "/Library/LaunchDaemons")
            }
        }
    }

    struct Item: Identifiable {
        let id: URL
        let label: String
        let program: String
        let scope: Scope
        let appURL: URL?
        var enabled: Bool
        var running: Bool
        var vendor: String {
            if let appURL { return appURL.deletingPathExtension().lastPathComponent }
            let parts = label.split(separator: ".")
            return parts.count > 1 ? String(parts[1]).capitalized : label
        }
    }

    var items: [Item] = []
    var loading = false
    var busy: Set<URL> = []
    var error: String?

    private var uid: String { String(getuid()) }

    func load() async {
        loading = true
        let disabledUser = await Self.disabled(domain: "gui/\(uid)")
        let disabledSystem = await Self.disabled(domain: "system")
        let running = await Self.runningLabels()
        var out: [Item] = []
        for scope in Scope.allCases {
            for plist in FS.children(scope.dir) where plist.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: plist),
                      let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let label = d["Label"] as? String else { continue }
                let prog = (d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first) ?? ""
                var appURL: URL?
                if let r = prog.range(of: ".app/") { appURL = URL(fileURLWithPath: String(prog[..<r.lowerBound]) + ".app") }
                let disabledSet = scope == .daemon ? disabledSystem : disabledUser
                let off = disabledSet[label] ?? (d["Disabled"] as? Bool ?? false)
                out.append(Item(id: plist, label: label, program: prog, scope: scope, appURL: appURL,
                                enabled: !off, running: running.contains(label)))
            }
        }
        withAnimation(.snappy) {
            items = out.sorted { ($0.scope.rawValue, $0.vendor) < ($1.scope.rawValue, $1.vendor) }
        }
        loading = false
    }

    /// label → disabled? from `launchctl print-disabled`.
    nonisolated static func disabled(domain: String) async -> [String: Bool] {
        let r = await Shell.exec("/bin/launchctl", ["print-disabled", domain])
        var out: [String: Bool] = [:]
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            out[label] = parts[1].hasPrefix("disabled") || parts[1].hasPrefix("true")
        }
        return out
    }

    nonisolated static func runningLabels() async -> Set<String> {
        let r = await Shell.exec("/bin/launchctl", ["list"])
        var out: Set<String> = []
        for line in r.out.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t")
            if cols.count == 3, cols[0] != "-" { out.insert(String(cols[2])) }
        }
        return out
    }

    func setEnabled(_ item: Item, _ on: Bool) async {
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        let domain = item.scope == .daemon ? "system" : "gui/\(uid)"
        let p = item.id.path
        let cmd = on
            ? "launchctl enable \(domain)/\(item.label); launchctl bootstrap \(domain) '\(p)' 2>/dev/null; true"
            : "launchctl disable \(domain)/\(item.label); launchctl bootout \(domain)/\(item.label) 2>/dev/null; true"
        let r = item.scope == .daemon ? await Shell.runAdmin(cmd) : await Shell.run(cmd)
        if r.code != 0 { error = r.out.contains("-128") ? nil : r.out; return }
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.snappy) {
                items[i].enabled = on
                if !on { items[i].running = false }
            }
        }
    }

    func remove(_ item: Item) async {
        await setEnabled(item, false)
        let ok = item.scope == .user ? FS.trash(item.id) : await Shell.adminTrash(item.id)
        if ok { withAnimation(.snappy) { items.removeAll { $0.id == item.id } } }
    }
}

// MARK: - Duplicate finder

@Observable @MainActor
final class Duplicates {
    struct FileRef: Identifiable {
        let id: URL
        let modified: Date?
        var selected: Bool
    }
    struct Group: Identifiable {
        let id: String           // hash
        let size: Int64
        var files: [FileRef]
        var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
    }

    var root: URL = home
    var minSize: Int64 = 1_000_000
    var groups: [Group] = []
    var scanning = false
    var hasScanned = false
    var status = ""
    var progress: Double = 0
    private var task: Task<Void, Never>?

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var selectedSize: Int64 { groups.reduce(0) { $0 + $1.size * Int64($1.files.filter(\.selected).count) } }
    var selectedCount: Int { groups.reduce(0) { $0 + $1.files.filter(\.selected).count } }

    func scan() {
        task?.cancel()
        scanning = true; hasScanned = true; progress = 0
        withAnimation { groups = [] }
        let root = root, minSize = minSize
        task = Task {
            let found = await Task.detached(priority: .userInitiated) {
                Duplicates.find(root: root, minSize: minSize) { text, p in
                    Task { @MainActor in self.status = text; self.progress = p }
                }
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(.spring) { groups = found.sorted { $0.wasted > $1.wasted } }
            scanning = false
        }
    }

    func stop() { task?.cancel(); scanning = false }

    nonisolated static func find(root: URL, minSize: Int64, progress: @escaping (String, Double) -> Void) -> [Group] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                     options: [.skipsPackageDescendants, .skipsHiddenFiles],
                                                     errorHandler: { _, _ in true }) else { return [] }
        let skip: Set<String> = [home.sub("Library").path, home.sub(".Trash").path]
        var bySize: [Int64: [(URL, Date?)]] = [:]
        var n = 0
        while let u = e.nextObject() as? URL {
            n += 1
            if n % 3000 == 0 {
                if Task.isCancelled { return [] }
                progress(T("Переглянуто \(Fmt.count(n)) файлів", "Scanned \(Fmt.count(n)) files"), 0.05)
            }
            if skip.contains(u.path) { e.skipDescendants(); continue }
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true,
                  let s = v.fileSize, Int64(s) >= minSize else { continue }
            bySize[Int64(s), default: []].append((u, v.contentModificationDate))
        }
        let candidates = bySize.filter { $0.value.count > 1 }
        var groups: [Group] = []
        var done = 0
        for (size, files) in candidates {
            if Task.isCancelled { return [] }
            done += 1
            progress(T("Порівнюю вміст: \(done) з \(candidates.count)", "Comparing contents: \(done) of \(candidates.count)"),
                     0.1 + 0.9 * Double(done) / Double(max(candidates.count, 1)))
            // Cheap pass on the first 64 KB, then a full hash for what still collides.
            var byHead: [String: [(URL, Date?)]] = [:]
            for f in files { if let h = hash(f.0, limit: 65_536) { byHead[h, default: []].append(f) } }
            for (_, same) in byHead where same.count > 1 {
                var byFull: [String: [(URL, Date?)]] = [:]
                for f in same { if let h = hash(f.0, limit: nil) { byFull[h, default: []].append(f) } }
                for (h, dup) in byFull where dup.count > 1 {
                    // Keep the oldest copy, pre-select the rest.
                    let sorted = dup.sorted { ($0.1 ?? .distantPast) < ($1.1 ?? .distantPast) }
                    let refs = sorted.enumerated().map { i, f in FileRef(id: f.0, modified: f.1, selected: i > 0) }
                    groups.append(Group(id: h, size: size, files: refs))
                }
            }
        }
        return groups
    }

    nonisolated static func hash(_ u: URL, limit: Int?) -> String? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var read = 0
        while true {
            let chunk = min(1 << 20, (limit ?? .max) - read)
            guard chunk > 0, let d = try? h.read(upToCount: chunk), !d.isEmpty else { break }
            hasher.update(data: d)
            read += d.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func toggle(_ file: URL, in gid: String) {
        guard let g = groups.firstIndex(where: { $0.id == gid }),
              let f = groups[g].files.firstIndex(where: { $0.id == file }) else { return }
        // Always keep at least one copy.
        if !groups[g].files[f].selected, groups[g].files.filter({ !$0.selected }).count <= 1 { NSSound.beep(); return }
        groups[g].files[f].selected.toggle()
    }

    func trashSelected() {
        var freed: Int64 = 0
        for g in groups.indices {
            let size = groups[g].size
            groups[g].files.removeAll { f in
                guard f.selected, FS.trash(f.id) else { return false }
                freed += size
                return true
            }
        }
        Stats.add(freed)
        withAnimation(.spring) { groups.removeAll { $0.files.count < 2 } }
    }
}
