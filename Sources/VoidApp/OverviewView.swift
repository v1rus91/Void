import SwiftUI

struct OverviewView: View {
    @Environment(SystemMonitor.self) private var s
    @Environment(Cleaner.self) private var cleaner
    @Environment(Router.self) private var router
    @AppStorage("totalFreed") private var totalFreed = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .overview, subtitle: "\(s.hostName) · \(s.chip) · \(s.osVersion)")
                hero
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    cpuCard
                    memoryCard
                    batteryCard
                }
                HStack(alignment: .top, spacing: 16) {
                    networkCard
                    systemCard
                }
            }
            .padding(28)
        }
    }

    private var hero: some View {
        let used = Double(s.diskUsed) / Double(max(s.diskTotal, 1))
        return GlassCard(padding: 26, radius: 28) {
            HStack(spacing: 30) {
                ZStack {
                    Ring(value: used, colors: used > 0.9 ? [.orange, .red] : [.cyan, .blue, .purple], width: 18)
                    VStack(spacing: 0) {
                        Text(Fmt.percent(used)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(T("зайнято", "used")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    Text(T("Сховище", "Storage")).font(.title2.bold())
                    StatLine(label: T("Використано", "Used"), value: Fmt.bytes(s.diskUsed), color: .blue)
                    StatLine(label: T("Вільно", "Free"), value: Fmt.bytes(s.diskFree), color: .green)
                    if s.diskPurgeable > 0 {
                        StatLine(label: T("З них очищуване системою", "Of which purgeable"), value: Fmt.bytes(s.diskPurgeable), color: .mint)
                    }
                    StatLine(label: T("Загалом", "Total"), value: Fmt.bytes(s.diskTotal))
                    if totalFreed > 0 {
                        StatLine(label: T("Звільнено Void за весь час", "Freed by Void, all time"), value: Fmt.bytes(Int64(totalFreed)), color: .pink)
                    }
                }
                .frame(maxWidth: 340)

                Spacer(minLength: 10)

                VStack(spacing: 12) {
                    if cleaner.total > 0 {
                        Text(Fmt.bytes(cleaner.total))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                        Text(T("можна звільнити", "can be freed")).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.pink.gradient)
                            .symbolEffect(.pulse, options: .repeating)
                        Text(T("Знайдемо сміття за секунди", "Find junk in seconds")).foregroundStyle(.secondary).font(.callout)
                    }
                    Button {
                        router.pane = .clean
                        if cleaner.phase == .idle { Task { await cleaner.scan() } }
                    } label: {
                        Label(cleaner.total > 0 ? T("Переглянути", "Review") : T("Сканувати", "Scan"), systemImage: "sparkle.magnifyingglass")
                            .font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pink)
                    .controlSize(.large)
                }
                .frame(minWidth: 200)
            }
        }
    }

    private var cpuCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: "cpu.fill", tint: .blue, size: 30)
                    Text(T("Процесор", "CPU")).font(.headline)
                    Spacer()
                    Text(Fmt.percent(s.cpu)).font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
                }
                Sparkline(values: s.cpuHistory, tint: .blue).frame(height: 54)
                    .animation(.linear(duration: 0.4), value: s.cpuHistory)
                Text(T("\(s.coreCount) ядер · за 3 хв", "\(s.coreCount) cores · last 3 min")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onTapGesture { router.pane = .monitor }
    }

    private var memoryCard: some View {
        let t = Double(max(s.memTotal, 1))
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: "memorychip.fill", tint: .purple, size: 30)
                    Text(T("Пам'ять", "Memory")).font(.headline)
                    Spacer()
                    Text("\(Fmt.bytes(s.memUsed)) / \(Fmt.bytes(s.memTotal))").font(.callout.bold().monospacedDigit())
                }
                GeometryReader { g in
                    HStack(spacing: 2) {
                        Capsule().fill(.purple.gradient).frame(width: g.size.width * Double(s.memApp) / t)
                        Capsule().fill(.orange.gradient).frame(width: g.size.width * Double(s.memWired) / t)
                        Capsule().fill(.pink.gradient).frame(width: g.size.width * Double(s.memCompressed) / t)
                        Capsule().fill(.primary.opacity(0.08))
                    }
                }
                .frame(height: 10)
                .animation(.smooth, value: s.memUsed)
                HStack(spacing: 14) {
                    legend(T("Програми", "Apps"), .purple, s.memApp)
                    legend(T("Системна", "Wired"), .orange, s.memWired)
                    legend(T("Стиснута", "Compressed"), .pink, s.memCompressed)
                }
                Text(T("Вільно \(Fmt.bytes(s.memFree)) · Кеш \(Fmt.bytes(s.memCached)) · Swap \(Fmt.bytes(s.swapUsed))",
                       "Free \(Fmt.bytes(s.memFree)) · Cache \(Fmt.bytes(s.memCached)) · Swap \(Fmt.bytes(s.swapUsed))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onTapGesture { router.pane = .monitor }
    }

    private func legend(_ t: String, _ c: Color, _ v: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { Circle().fill(c).frame(width: 6, height: 6); Text(t) }
                .font(.caption2).foregroundStyle(.secondary)
            Text(Fmt.bytes(v)).font(.caption.monospacedDigit().weight(.medium))
        }
    }

    private var batteryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: s.battery == nil ? "powerplug.fill" : (s.charging ? "battery.100percent.bolt" : "battery.75percent"),
                             tint: .green, size: 30)
                    Text(T("Живлення", "Power")).font(.headline)
                    Spacer()
                    if let b = s.battery {
                        Text("\(b)%").font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
                    }
                }
                if let b = s.battery {
                    SizeBar(fraction: Double(b) / 100, tint: b < 20 ? .red : .green)
                    StatLine(label: T("Стан", "State"), value: s.charging ? T("Заряджається", "Charging") : (s.onAC ? T("Від мережі", "On AC") : T("Від батареї", "On battery")))
                    if let m = s.timeRemaining {
                        StatLine(label: s.charging ? T("До повного", "Until full") : T("Залишилось", "Remaining"), value: Fmt.duration(Double(m) * 60))
                    }
                    if let h = s.batteryHealth { StatLine(label: T("Здоров'я батареї", "Battery health"), value: Fmt.percent(h)) }
                    if let c = s.batteryCycles { StatLine(label: T("Цикли заряду", "Cycle count"), value: "\(c)") }
                } else {
                    Text(T("Працює від мережі", "Running on AC power")).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var networkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: "network", tint: .cyan, size: 30)
                    Text(T("Мережа", "Network")).font(.headline)
                    Spacer()
                }
                HStack(spacing: 18) {
                    speed("arrow.down", .cyan, s.netIn, T("Завантаження", "Download"))
                    speed("arrow.up", .orange, s.netOut, T("Вивантаження", "Upload"))
                }
                ZStack {
                    Sparkline(values: normalized(s.netInHistory, s.netOutHistory).0, tint: .cyan)
                    Sparkline(values: normalized(s.netInHistory, s.netOutHistory).1, tint: .orange)
                }
                .frame(height: 50)
            }
        }
        .onTapGesture { router.pane = .monitor }
    }

    private func speed(_ sym: String, _ c: Color, _ v: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: sym).font(.caption).foregroundStyle(c)
            Text(Fmt.speed(v)).font(.title3.bold().monospacedDigit()).contentTransition(.numericText())
        }
    }

    private var systemCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: "laptopcomputer", tint: .gray, size: 30)
                    Text(T("Система", "System")).font(.headline)
                }
                StatLine(label: T("Комп'ютер", "Computer"), value: s.hostName)
                StatLine(label: T("Чіп", "Chip"), value: s.chip)
                StatLine(label: T("Система", "OS"), value: s.osVersion)
                StatLine(label: T("Без перезавантаження", "Uptime"), value: Fmt.duration(s.uptime))
                StatLine(label: T("Температурний стан", "Thermal state"), value: s.thermalText)
                if let d = cleaner.lastScan {
                    StatLine(label: T("Останнє сканування", "Last scan"), value: Fmt.relative(d))
                }
            }
        }
    }
}

/// Scales two series to a shared 0…1 range.
func normalized(_ a: [Double], _ b: [Double]) -> ([Double], [Double]) {
    let m = max(a.max() ?? 0, b.max() ?? 0, 1)
    return (a.map { $0 / m }, b.map { $0 / m })
}
