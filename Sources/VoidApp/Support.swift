import SwiftUI
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser

extension URL {
    func sub(_ path: String) -> URL { appending(path: path) }
}

// MARK: - Localization (Ukrainian / English, switchable at runtime)

enum Loc {
    static var en: Bool {
        switch UserDefaults.standard.string(forKey: "lang") ?? "system" {
        case "en": return true
        case "uk": return false
        default:
            let p = Locale.preferredLanguages.first ?? "en"
            return !(p.hasPrefix("uk") || p.hasPrefix("ru"))
        }
    }
    static var locale: Locale { Locale(identifier: en ? "en_US" : "uk_UA") }
}

/// Picks the string for the current UI language.
func T(_ uk: String, _ en: String) -> String { Loc.en ? en : uk }

/// A pair of translations, resolved when displayed.
struct LS: Sendable {
    let uk: String
    let en: String
    init(_ uk: String, _ en: String) { self.uk = uk; self.en = en }
    var s: String { T(uk, en) }
}

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        let units = Loc.en ? ["B", "KB", "MB", "GB", "TB"] : ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        guard b > 0 else { return "0 " + units[1] }
        var v = Double(b), i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        let digits = i == 0 ? 0 : (i >= 3 ? 2 : 1)
        return v.formatted(.number.precision(.fractionLength(0...digits)).locale(Loc.locale)) + " " + units[i]
    }
    static func speed(_ bps: Double) -> String { bytes(Int64(bps)) + T("/с", "/s") }
    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        var c = Calendar.current
        c.locale = Loc.locale
        f.calendar = c
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: t) ?? ""
    }
    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Loc.locale
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: .now)
    }
    static func path(_ u: URL) -> String {
        u.path.replacingOccurrences(of: home.path, with: "~")
    }
    static func count(_ n: Int) -> String { n.formatted(.number.locale(Loc.locale)) }
}

/// Lifetime counter of space freed by Void.
enum Stats {
    static func add(_ bytes: Int64) {
        guard bytes > 0 else { return }
        let d = UserDefaults.standard
        d.set(d.integer(forKey: "totalFreed") + Int(bytes), forKey: "totalFreed")
        d.set(d.integer(forKey: "cleanCount") + 1, forKey: "cleanCount")
    }
}

// MARK: - File system helpers

enum FS {
    static let fm = FileManager.default

    static func children(_ u: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [])) ?? []
    }

    static func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }

    static func isDirectory(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    static func isPackage(_ u: URL) -> Bool {
        (try? u.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }

    static func modified(_ u: URL) -> Date? {
        try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Human name for a bundle-id-like folder name (com.spotify.client → Spotify).
    static func prettyName(_ u: URL) -> String {
        let n = u.lastPathComponent
        if n.contains("."), !n.hasSuffix(".log"),
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n) {
            return app.deletingPathExtension().lastPathComponent
        }
        return n
    }

    static func trash(_ u: URL) -> Bool {
        (try? fm.trashItem(at: u, resultingItemURL: nil)) != nil
    }
}

enum DiskSizer {
    private static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]

    /// Allocated size on disk, recursive. Honours task cancellation.
    static func size(of url: URL) -> Int64 {
        guard let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true { return Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var n = 0
        while let f = e.nextObject() as? URL {
            n += 1
            if n % 2000 == 0, Task.isCancelled { break }
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func sizes(_ urls: [URL]) async -> [URL: Int64] {
        await withTaskGroup(of: (URL, Int64).self) { g in
            for u in urls { g.addTask { (u, size(of: u)) } }
            var out: [URL: Int64] = [:]
            for await (u, s) in g { out[u] = s }
            return out
        }
    }
}

enum Icons {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(_ u: URL) -> NSImage {
        let k = u.path as NSString
        if let i = cache.object(forKey: k) { return i }
        let i = NSWorkspace.shared.icon(forFile: u.path)
        cache.setObject(i, forKey: k)
        return i
    }
}

// MARK: - Shell

enum Shell {
    @discardableResult
    static func exec(_ path: String, _ args: [String]) async -> (code: Int32, out: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return (Int32(-1), error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    @discardableResult
    static func run(_ cmd: String) async -> (code: Int32, out: String) {
        await exec("/bin/zsh", ["-c", cmd])
    }

    static func appleString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Runs a shell command as root via the native macOS password prompt.
    @discardableResult
    static func runAdmin(_ cmd: String) async -> (code: Int32, out: String) {
        await exec("/usr/bin/osascript", ["-e", "do shell script \(appleString(cmd)) with administrator privileges"])
    }

    /// Moves a root-owned item to the user's Trash with admin rights.
    static func adminTrash(_ u: URL) async -> Bool {
        let script = "do shell script \"mv \" & quoted form of \(appleString(u.path)) & \" \" & quoted form of \(appleString(home.sub(".Trash").path + "/")) with administrator privileges"
        return await exec("/usr/bin/osascript", ["-e", script]).code == 0
    }
}

func reveal(_ u: URL) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
