import SwiftUI
import Charts

struct ChartSeries: Identifiable {
    let id: String
    let color: Color
    let values: [Double]
}

struct HistoryChart: View {
    let series: [ChartSeries]
    var maxY: Double?
    var format: (Double) -> String

    var body: some View {
        let top = maxY ?? max((series.flatMap(\.values).max() ?? 0) * 1.15, 1)
        Chart {
            ForEach(series) { s in
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), y: .value("v", v), series: .value("s", s.id), stacking: .unstacked)
                        .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.32), s.color.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", s.id))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...(SystemMonitor.historyLength - 1))
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(format(d)).font(.caption2).monospacedDigit() }
                }
            }
        }
        .chartLegend(.hidden)
    }
}

struct MonitorView: View {
    @Environment(SystemMonitor.self) private var s
    private let cols = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .monitor, subtitle: T("Живі показники кожні \(Int(SystemMonitor.interval)) с · історія за 3 хвилини",
                                                       "Live stats every \(Int(SystemMonitor.interval)) s · 3‑minute history"))
                gauges
                LazyVGrid(columns: cols, spacing: 16) {
                    cpuCard
                    memoryCard
                    networkCard
                    diskCard
                    gpuCard
                    loadCard
                }
                HStack(alignment: .top, spacing: 16) {
                    procsCard
                    appsCard
                }
            }
            .padding(28)
        }
    }

    // MARK: gauges

    private var gauges: some View {
        HStack(spacing: 16) {
            gauge(T("Процесор", "CPU"), s.cpu, [.cyan, .blue], "cpu")
            gauge("GPU", s.gpu ?? 0, [.mint, .green], "cube.transparent")
            gauge(T("Пам'ять", "Memory"), Double(s.memUsed) / Double(max(s.memTotal, 1)), [.pink, .purple], "memorychip")
            gauge(T("Диск", "Disk"), Double(s.diskUsed) / Double(max(s.diskTotal, 1)), [.orange, .red], "internaldrive")
        }
    }

    private func gauge(_ title: String, _ v: Double, _ colors: [Color], _ sym: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Ring(value: v, colors: colors, width: 8)
                Image(systemName: sym).font(.callout.weight(.semibold)).foregroundStyle(colors.last!)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(Fmt.percent(v)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: cards

    private func card<C: View>(_ title: String, _ sym: String, _ tint: Color, value: String, @ViewBuilder _ content: () -> C) -> some View {
        GlassCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconTile(symbol: sym, tint: tint, size: 28)
                    Text(title).font(.headline)
                    Spacer()
                    Text(value).font(.title3.bold().monospacedDigit()).contentTransition(.numericText())
                }
                content()
            }
        }
    }

    private func legend(_ items: [(String, Color, String)]) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.0) { name, c, v in
                HStack(spacing: 5) {
                    Circle().fill(c).frame(width: 7, height: 7)
                    Text(name).foregroundStyle(.secondary)
                    Text(v).monospacedDigit().fontWeight(.medium)
                }
                .font(.caption)
            }
        }
    }

    private var cpuCard: some View {
        card(T("Процесор", "CPU"), "cpu.fill", .blue, value: Fmt.percent(s.cpu)) {
            HistoryChart(series: [ChartSeries(id: "cpu", color: .blue, values: s.cpuHistory)], maxY: 1) { Fmt.percent($0) }
                .frame(height: 120)
            legend([(T("Користувач", "User"), .blue, Fmt.percent(s.cpuUser)),
                    (T("Система", "System"), .red, Fmt.percent(s.cpuSystem)),
                    (T("Простій", "Idle"), .gray, Fmt.percent(max(0, 1 - s.cpu)))])
            if !s.cores.isEmpty {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(s.cores.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 3) {
                            GeometryReader { g in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(LinearGradient(colors: [.cyan, v > 0.8 ? .red : .blue], startPoint: .bottom, endPoint: .top))
                                        .frame(height: max(2, g.size.height * v))
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.06)))
                            Text("\(i + 1)").font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 54)
                .animation(.smooth, value: s.cores)
            }
        }
    }

    private var memoryCard: some View {
        let pressure = 1 - Double(s.memPressure) / 100
        return card(T("Пам'ять", "Memory"), "memorychip.fill", .purple, value: Fmt.bytes(s.memUsed)) {
            HistoryChart(series: [ChartSeries(id: "mem", color: .purple, values: s.memHistory)], maxY: 1) { Fmt.percent($0) }
                .frame(height: 120)
            legend([(T("Вільно", "Free"), .green, Fmt.bytes(s.memFree)),
                    (T("Кеш", "Cache"), .gray, Fmt.bytes(s.memCached)),
                    ("Swap", .orange, Fmt.bytes(s.swapUsed))])
            HStack(spacing: 8) {
                Text(T("Тиск пам'яті", "Memory pressure")).font(.caption).foregroundStyle(.secondary)
                SizeBar(fraction: pressure, tint: pressure > 0.7 ? .red : pressure > 0.4 ? .orange : .green)
                Text(Fmt.percent(pressure)).font(.caption.monospacedDigit())
            }
        }
    }

    private var networkCard: some View {
        card(T("Мережа", "Network"), "network", .cyan, value: "↓ " + Fmt.speed(s.netIn)) {
            HistoryChart(series: [ChartSeries(id: "in", color: .cyan, values: s.netInHistory),
                                  ChartSeries(id: "out", color: .orange, values: s.netOutHistory)]) { Fmt.speed($0) }
                .frame(height: 120)
            legend([(T("Отримано", "Down"), .cyan, Fmt.speed(s.netIn)),
                    (T("Надіслано", "Up"), .orange, Fmt.speed(s.netOut))])
            Text(T("З моменту ввімкнення: ↓ \(Fmt.bytes(Int64(s.netTotalIn))) · ↑ \(Fmt.bytes(Int64(s.netTotalOut)))",
                   "Since boot: ↓ \(Fmt.bytes(Int64(s.netTotalIn))) · ↑ \(Fmt.bytes(Int64(s.netTotalOut)))"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var diskCard: some View {
        card(T("Диск (I/O)", "Disk I/O"), "internaldrive.fill", .orange, value: Fmt.speed(s.diskRead + s.diskWrite)) {
            HistoryChart(series: [ChartSeries(id: "r", color: .green, values: s.diskReadHistory),
                                  ChartSeries(id: "w", color: .red, values: s.diskWriteHistory)]) { Fmt.speed($0) }
                .frame(height: 120)
            legend([(T("Читання", "Read"), .green, Fmt.speed(s.diskRead)),
                    (T("Запис", "Write"), .red, Fmt.speed(s.diskWrite))])
            Text(T("Вільно \(Fmt.bytes(s.diskFree)) з \(Fmt.bytes(s.diskTotal))", "\(Fmt.bytes(s.diskFree)) free of \(Fmt.bytes(s.diskTotal))"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var gpuCard: some View {
        card(T("Графіка", "Graphics"), "cube.transparent.fill", .green, value: s.gpu.map(Fmt.percent) ?? "—") {
            HistoryChart(series: [ChartSeries(id: "gpu", color: .green, values: s.gpuHistory)], maxY: 1) { Fmt.percent($0) }
                .frame(height: 120)
            Text(T("Завантаженість графічного ядра \(s.chip)", "\(s.chip) GPU utilization"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var loadCard: some View {
        card(T("Навантаження системи", "System load"), "speedometer", .indigo, value: String(format: "%.2f", s.load.0)) {
            VStack(spacing: 10) {
                loadRow(T("1 хвилина", "1 minute"), s.load.0)
                loadRow(T("5 хвилин", "5 minutes"), s.load.1)
                loadRow(T("15 хвилин", "15 minutes"), s.load.2)
            }
            Divider()
            StatLine(label: T("Процесів", "Processes"), value: Fmt.count(s.procCount))
            StatLine(label: T("Температурний стан", "Thermal state"), value: s.thermalText)
            StatLine(label: T("Без перезавантаження", "Uptime"), value: Fmt.duration(s.uptime))
        }
    }

    private func loadRow(_ label: String, _ v: Double) -> some View {
        let f = v / Double(max(s.coreCount, 1))
        return HStack(spacing: 10) {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            SizeBar(fraction: f, tint: f > 1 ? .red : f > 0.7 ? .orange : .indigo)
            Text(String(format: "%.2f", v)).font(.callout.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }

    private var procsCard: some View {
        GlassCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: "flame.fill", tint: .orange, size: 28)
                    Text(T("Процеси за CPU", "Top processes by CPU")).font(.headline)
                }
                ForEach(s.topProcs) { p in
                    HStack(spacing: 10) {
                        Text(p.name).lineLimit(1).frame(minWidth: 120, alignment: .leading)
                        SizeBar(fraction: min(p.cpu / 100, 1), tint: .orange)
                        Text(String(format: "%.0f%%", p.cpu)).monospacedDigit().frame(width: 50, alignment: .trailing)
                        Text(Fmt.bytes(p.mem)).foregroundStyle(.secondary).font(.caption.monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var appsCard: some View {
        GlassCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: "app.badge.fill", tint: .purple, size: 28)
                    Text(T("Програми за пам'яттю", "Apps by memory")).font(.headline)
                }
                ForEach(s.topApps) { a in AppMemRow(app: a) }
            }
        }
    }
}

struct AppMemRow: View {
    let app: SystemMonitor.AppMem
    @Environment(SystemMonitor.self) private var s
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            if let i = app.icon { Image(nsImage: i).resizable().frame(width: 22, height: 22) }
            Text(app.name).lineLimit(1)
            Spacer()
            Text(Fmt.bytes(app.mem)).monospacedDigit().foregroundStyle(.secondary)
            Button { s.quit(app.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .opacity(hover ? 1 : 0.35)
                .help(T("Закрити програму", "Quit app"))
        }
        .font(.callout)
        .onHover { hover = $0 }
    }
}
