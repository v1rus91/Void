import Foundation
import AppKit
import IOKit
import IOKit.ps
import SystemConfiguration
import UserNotifications
import Observation

@Observable @MainActor
final class SystemMonitor {
    struct Proc: Identifiable { let id = UUID(); let name: String; let cpu: Double; let mem: Int64 }
    struct AppMem: Identifiable { let id: pid_t; let name: String; let icon: NSImage?; let mem: Int64 }

    static let historyLength = 90
    static let interval: Double = 2

    // Disk
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0          // incl. purgeable
    var diskPurgeable: Int64 = 0
    var diskRead: Double = 0         // bytes/s
    var diskWrite: Double = 0
    var diskReadHistory = SystemMonitor.zeros
    var diskWriteHistory = SystemMonitor.zeros

    // CPU / GPU
    var cpu: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuHistory = SystemMonitor.zeros
    var cores: [Double] = []
    var gpu: Double?
    var gpuHistory = SystemMonitor.zeros
    var load: (Double, Double, Double) = (0, 0, 0)
    var thermal: ProcessInfo.ThermalState = .nominal

    // Memory
    let memTotal = Int64(ProcessInfo.processInfo.physicalMemory)
    var memApp: Int64 = 0
    var memWired: Int64 = 0
    var memCompressed: Int64 = 0
    var memCached: Int64 = 0
    var memHistory = SystemMonitor.zeros
    var memPressure: Int = 100       // % "free level" from the kernel
    var swapUsed: Int64 = 0

    // Network
    var netIn: Double = 0
    var netOut: Double = 0
    var netInHistory = SystemMonitor.zeros
    var netOutHistory = SystemMonitor.zeros
    var netTotalIn: UInt64 = 0
    var netTotalOut: UInt64 = 0

    // Power
    var battery: Int?
    var charging = false
    var onAC = true
    var batteryCycles: Int?
    var batteryHealth: Double?
    var timeRemaining: Int?          // minutes

    var uptime: TimeInterval = 0
    var topProcs: [Proc] = []
    var topApps: [AppMem] = []
    var procCount = 0

    let chip: String
    let hostName: String
    let osVersion: String
    let coreCount = ProcessInfo.processInfo.activeProcessorCount

    var memUsed: Int64 { memApp + memWired + memCompressed }
    var memFree: Int64 { max(0, memTotal - memUsed) }
    var diskUsed: Int64 { diskTotal - diskFree }

    static var zeros: [Double] { Array(repeating: 0, count: historyLength) }

    private var prevTicks: [UInt64]?
    private var prevCoreTicks: [[UInt64]] = []
    private var prevNet: (UInt64, UInt64, Date)?
    private var prevDisk: (UInt64, UInt64, Date)?
    private var tick = 0
    private var lastAlert: Date?

    init() {
        chip = Self.sysctlString("machdep.cpu.brand_string")
        hostName = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        loadBatteryHealth()
        refresh()
    }

    private var running = false

    /// Polling loop; safe to start from several views — only one runs.
    func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while !Task.isCancelled {
            refresh()
            if tick % 2 == 0 { await refreshProcs() }
            if tick % 150 == 0 { checkLowDisk() }
            tick += 1
            try? await Task.sleep(for: .seconds(Self.interval))
        }
    }

    func refresh() {
        refreshDisk()
        refreshCPU()
        refreshCores()
        refreshGPU()
        refreshMemory()
        refreshNetwork()
        refreshDiskIO()
        refreshBattery()
        samples += 1
        uptime = ProcessInfo.processInfo.systemUptime
        thermal = ProcessInfo.processInfo.thermalState
        var l = [Double](repeating: 0, count: 3)
        if getloadavg(&l, 3) == 3 { load = (l[0], l[1], l[2]) }
    }

    private var samples = 0

    /// Appends to a history; the first real sample fills the whole window so charts don't start with a cliff.
    private func push(_ a: inout [Double], _ v: Double) {
        if samples < 2 { a = Array(repeating: v, count: Self.historyLength); return }
        a.removeFirst()
        a.append(v)
    }

    func refreshDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        let strict = Int64(v.volumeAvailableCapacity ?? 0)
        diskFree = max(v.volumeAvailableCapacityForImportantUsage ?? strict, strict)
        diskPurgeable = max(0, diskFree - strict)
    }

    private func refreshCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        let ticks = [UInt64(t.0), UInt64(t.1), UInt64(t.2), UInt64(t.3)] // user, system, idle, nice
        if let p = prevTicks {
            let d = zip(ticks, p).map { $0 &- $1 }
            let total = Double(d.reduce(0, +))
            if total > 0 {
                cpuUser = Double(d[0] + d[3]) / total
                cpuSystem = Double(d[1]) / total
                cpu = cpuUser + cpuSystem
            }
        }
        prevTicks = ticks
        push(&cpuHistory, cpu)
    }

    private func refreshCores() {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let infoArray else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var now: [[UInt64]] = []
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            now.append((0..<Int(CPU_STATE_MAX)).map { UInt64(UInt32(bitPattern: infoArray[base + $0])) })
        }
        if prevCoreTicks.count == now.count {
            cores = zip(now, prevCoreTicks).map { n, p in
                let d = zip(n, p).map { $0 &- $1 }
                let total = Double(d.reduce(0, +))
                return total > 0 ? Double(d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]) / total : 0
            }
        }
        prevCoreTicks = now
    }

    private func refreshGPU() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var best: Double?
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let u = stats["Device Utilization %"] as? Int {
                best = max(best ?? 0, Double(u) / 100)
            }
        }
        gpu = best
        push(&gpuHistory, best ?? 0)
    }

    private func refreshMemory() {
        var s = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Int64(vm_kernel_page_size)
        memApp = (Int64(s.internal_page_count) - Int64(s.purgeable_count)) * page
        memWired = Int64(s.wire_count) * page
        memCompressed = Int64(s.compressor_page_count) * page
        memCached = (Int64(s.external_page_count) + Int64(s.purgeable_count)) * page

        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 { swapUsed = Int64(xsw.xsu_used) }

        var level: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 { memPressure = Int(level) }

        push(&memHistory, Double(memUsed) / Double(max(memTotal, 1)))
    }

    private func refreshNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var i: UInt64 = 0, o: UInt64 = 0
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data else { continue }
            guard String(cString: a.ifa_name).hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            i += UInt64(d.ifi_ibytes)
            o += UInt64(d.ifi_obytes)
        }
        let now = Date()
        if let p = prevNet, i >= p.0, o >= p.1 {
            let dt = now.timeIntervalSince(p.2)
            if dt > 0 {
                netIn = Double(i - p.0) / dt
                netOut = Double(o - p.1) / dt
            }
        }
        netTotalIn = i
        netTotalOut = o
        prevNet = (i, o, now)
        push(&netInHistory, netIn)
        push(&netOutHistory, netOut)
    }

    private func refreshDiskIO() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var r: UInt64 = 0, w: UInt64 = 0
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            if let st = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                r += (st["Bytes (Read)"] as? UInt64) ?? 0
                w += (st["Bytes (Write)"] as? UInt64) ?? 0
            }
        }
        let now = Date()
        if let p = prevDisk, r >= p.0, w >= p.1 {
            let dt = now.timeIntervalSince(p.2)
            if dt > 0 {
                diskRead = Double(r - p.0) / dt
                diskWrite = Double(w - p.1) / dt
            }
        }
        prevDisk = (r, w, now)
        push(&diskReadHistory, diskRead)
        push(&diskWriteHistory, diskWrite)
    }

    private func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                battery = cap * 100 / max
            }
            charging = d[kIOPSIsChargingKey] as? Bool ?? false
            onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let m = d[key] as? Int, m > 0 { timeRemaining = m } else { timeRemaining = nil }
        }
    }

    private func loadBatteryHealth() {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard s != 0 else { return }
        defer { IOObjectRelease(s) }
        func prop(_ k: String) -> Int? {
            IORegistryEntryCreateCFProperty(s, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        batteryCycles = prop("CycleCount")
        if let design = prop("DesignCapacity"), design > 0,
           let maxCap = prop("AppleRawMaxCapacity") ?? prop("NominalChargeCapacity") {
            batteryHealth = min(1, Double(maxCap) / Double(design))
        }
    }

    private func refreshProcs() async {
        let r = await Shell.exec("/bin/ps", ["-Aceo", "pcpu=,rss=,comm=", "-r"])
        var out: [Proc] = []
        let lines = r.out.split(separator: "\n")
        procCount = lines.count
        for line in lines.prefix(10) {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let c = Double(parts[0]), let m = Int64(parts[1]) else { continue }
            let name = String(parts[2])
            if name == "ps" { continue }
            out.append(Proc(name: name, cpu: c, mem: m * 1024))
        }
        topProcs = Array(out.prefix(8))

        topApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in
                let m = Self.footprint(app.processIdentifier)
                return m > 0 ? AppMem(id: app.processIdentifier, name: app.localizedName ?? "?", icon: app.icon, mem: m) : nil
            }
            .sorted { $0.mem > $1.mem }
            .prefix(6)
            .map { $0 }
    }

    static func footprint(_ pid: pid_t) -> Int64 {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? Int64(info.ri_phys_footprint) : 0
    }

    func quit(_ pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
        topApps.removeAll { $0.id == pid }
    }

    // MARK: low disk notification

    private func checkLowDisk() {
        let d = UserDefaults.standard
        guard d.object(forKey: "lowDiskAlert") as? Bool ?? true else { return }
        let limitGB = d.object(forKey: "lowDiskGB") as? Int ?? 20
        guard diskTotal > 0, diskFree < Int64(limitGB) * 1_000_000_000 else { return }
        if let l = lastAlert, Date.now.timeIntervalSince(l) < 6 * 3600 { return }
        lastAlert = .now
        let c = UNMutableNotificationContent()
        c.title = T("Закінчується місце на диску", "Running out of disk space")
        c.body = T("Вільно лише \(Fmt.bytes(diskFree)). Відкрийте Void, щоб звільнити місце.",
                   "Only \(Fmt.bytes(diskFree)) free. Open Void to free up space.")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowdisk", content: c, trigger: nil))
    }

    var thermalText: String {
        switch thermal {
        case .nominal: T("Норма", "Normal")
        case .fair: T("Тепло", "Warm")
        case .serious: T("Гаряче", "Hot")
        case .critical: T("Критично", "Critical")
        @unknown default: "—"
        }
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
