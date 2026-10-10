import SwiftUI

// MARK: - Analyzer

struct AnalyzerView: View {
    @Environment(Analyzer.self) private var a
    private let palette: [Color] = [.purple, .blue, .pink, .orange, .teal, .indigo, .green, .cyan]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .analyze, subtitle: T("Що саме займає місце — тисніть на теку, щоб зайти глибше", "What takes up space — click a folder to drill in")) {
                    Menu {
                        Button(T("Домівка", "Home"), systemImage: "house") { a.setRoot(home) }
                        Button(T("Програми", "Applications"), systemImage: "app") { a.setRoot(URL(fileURLWithPath: "/Applications")) }
                        Button(T("Бібліотека", "Library"), systemImage: "books.vertical") { a.setRoot(home.sub("Library")) }
                    } label: { Label(T("Початок", "Start at"), systemImage: "folder") }
                        .menuStyle(.button).buttonStyle(.glass).fixedSize()
                    Button(T("Оновити", "Refresh"), systemImage: "arrow.clockwise") { a.load(force: true) }.buttonStyle(.glass)
                }

                breadcrumbs

                GlassCard(padding: 22, radius: 26) {
                    HStack(alignment: .center, spacing: 24) {
                        donut.frame(width: 150, height: 150)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(FileManager.default.displayName(atPath: a.current.path)).font(.title2.bold())
                            Text(Fmt.bytes(a.total)).font(.system(size: 30, weight: .heavy, design: .rounded))
                                .contentTransition(.numericText()).monospacedDigit()
                            HStack(spacing: 6) {
                                if a.loading { ProgressView().controlSize(.small) }
                                Text(a.loading ? T("Рахую розміри…", "Calculating sizes…") : T("\(a.entries.count) об'єктів", "\(a.entries.count) items"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }

                VStack(spacing: 2) {
                    let maxS = Double(max(a.maxSize, 1))
                    ForEach(Array(a.entries.enumerated()), id: \.element.id) { i, e in
                        row(e, color: palette[i % palette.count], fraction: Double(e.size ?? 0) / maxS)
                    }
                    if !a.loading && a.entries.isEmpty {
                        EmptyState(symbol: "folder", title: T("Порожньо", "Empty"), text: T("Тут немає файлів або немає доступу.", "No files here or no access."))
                    }
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
            .padding(28)
        }
        .onAppear { if a.entries.isEmpty { a.load() } }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(a.stack.enumerated()), id: \.offset) { i, u in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    Button(i == 0 ? Fmt.path(u) : u.lastPathComponent) { a.go(to: i) }
                        .buttonStyle(.glass).controlSize(.small)
                        .disabled(i == a.stack.count - 1)
                }
            }
        }
    }

    private var donut: some View {
        let top = Array(a.entries.prefix(8))
        let total = Double(max(a.total, 1))
        var start = 0.0
        let slices: [(Double, Double, Color)] = top.enumerated().map { i, e in
            let f = Double(e.size ?? 0) / total
            defer { start += f }
            return (start, start + f, palette[i % palette.count])
        }
        return ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: 22)
            ForEach(Array(slices.enumerated()), id: \.offset) { _, s in
                Circle().trim(from: s.0, to: max(s.0, s.1 - 0.004))
                    .stroke(s.2.gradient, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.smooth, value: a.total)
    }

    private func row(_ e: Analyzer.Entry, color: Color, fraction: Double) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: Icons.icon(e.url)).resizable().frame(width: 24, height: 24)
            Text(e.name).lineLimit(1).frame(minWidth: 160, alignment: .leading)
            SizeBar(fraction: fraction, tint: color)
            Group {
                if let s = e.size {
                    Text(Fmt.bytes(s)).monospacedDigit()
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 90, alignment: .trailing)
            Image(systemName: "chevron.right").foregroundStyle(.secondary).opacity(e.isDir ? 1 : 0).font(.caption)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { if e.isDir { a.open(e.url) } }
        .contextMenu {
            Button(T("Показати у Finder", "Show in Finder"), systemImage: "folder") { reveal(e.url) }
            Divider()
            Button(T("Перемістити в Кошик", "Move to Trash"), systemImage: "trash", role: .destructive) { a.trash(e) }
        }
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @Environment(LargeFiles.self) private var lf

    var body: some View {
        @Bindable var lf = lf
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .large, subtitle: T("Забуті відео, образи дисків, архіви — у вашій домашній теці", "Forgotten videos, disk images and archives in your home folder"))

                GlassCard(padding: 18, radius: 22) {
                    HStack(spacing: 16) {
                        Picker(T("Більше ніж", "Larger than"), selection: $lf.threshold) {
                            Text(Fmt.bytes(100_000_000)).tag(Int64(100_000_000))
                            Text(Fmt.bytes(500_000_000)).tag(Int64(500_000_000))
                            Text(Fmt.bytes(1_000_000_000)).tag(Int64(1_000_000_000))
                            Text(Fmt.bytes(5_000_000_000)).tag(Int64(5_000_000_000))
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 340)
                        Toggle(T("Включно з ~/Library", "Include ~/Library"), isOn: $lf.includeLibrary).toggleStyle(.switch).controlSize(.small)
                        Spacer()
                        if lf.scanning {
                            Text(Fmt.count(lf.scanned) + T(" файлів", " files")).monospacedDigit().foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                            ProgressView().controlSize(.small)
                            Button(T("Стоп", "Stop")) { lf.stop() }.buttonStyle(.glass)
                        } else {
                            Button { lf.scan() } label: { Label(T("Знайти", "Find"), systemImage: "magnifyingglass").font(.headline) }
                                .buttonStyle(.glassProminent).tint(.orange)
                        }
                    }
                }

                if lf.selectedCount > 0 {
                    HStack {
                        Text(T("Обрано ", "Selected ") + "\(lf.selectedCount) · \(Fmt.bytes(lf.selectedSize))").font(.headline)
                        Spacer()
                        Button(T("Перемістити в Кошик", "Move to Trash"), systemImage: "trash") { lf.trashSelected() }
                            .buttonStyle(.glassProminent).tint(.red)
                    }
                    .padding(14)
                    .glassEffect(.regular.tint(.orange.opacity(0.1)), in: .rect(cornerRadius: 18))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !lf.files.isEmpty {
                    let maxS = Double(lf.files.first?.size ?? 1)
                    LazyVStack(spacing: 2) {
                        ForEach(lf.files) { f in
                            HStack(spacing: 10) {
                                CheckButton(state: f.selected ? .on : .off, tint: .orange) { lf.toggle(f.id) }
                                Image(nsImage: Icons.icon(f.id)).resizable().frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.id.lastPathComponent).lineLimit(1)
                                    Text(Fmt.path(f.id.deletingLastPathComponent()) + (f.modified.map { T(" · змінено ", " · modified ") + Fmt.relative($0) } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 12)
                                SizeBar(fraction: Double(f.size) / maxS, tint: .orange).frame(width: 100)
                                Text(Fmt.bytes(f.size)).monospacedDigit().fontWeight(.medium).frame(width: 80, alignment: .trailing)
                                Button { reveal(f.id) } label: { Image(systemName: "arrow.right.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help(T("Показати у Finder", "Show in Finder"))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                        }
                    }
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                } else if lf.hasScanned && !lf.scanning {
                    EmptyState(symbol: "checkmark.circle", title: T("Нічого не знайдено", "Nothing found"), text: T("Немає файлів, більших за обраний поріг.", "No files above the selected size."), tint: .green)
                } else if !lf.scanning {
                    EmptyState(symbol: "doc.on.doc", title: T("Пошук великих файлів", "Find large files"), text: T("Оберіть поріг і натисніть «Знайти». Файли переміщуються в Кошик — їх можна відновити.", "Pick a size and press Find. Files go to the Trash, so they can be restored."), tint: .orange)
                }
            }
            .padding(28)
            .animation(.snappy, value: lf.selectedCount)
        }
    }
}

// MARK: - Uninstaller

struct UninstallView: View {
    @Environment(Uninstaller.self) private var u
    @State private var confirm = false

    var body: some View {
        @Bindable var u = u
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(pane: .uninstall, subtitle: T("Видаляйте програми разом із усіма їхніми слідами", "Remove apps together with all their leftovers"))
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    HStack {
                        TextField(T("Пошук", "Search"), text: $u.search).textFieldStyle(.plain)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                        Picker("", selection: $u.sort) {
                            ForEach(Uninstaller.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    List(u.visible, selection: Binding(get: { u.selectedID }, set: { u.select($0) })) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: Icons.icon(app.id)).resizable().frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).lineLimit(1)
                                Text(app.lastUsed.map { T("Відкривалась ", "Opened ") + Fmt.relative($0) } ?? T("Не відкривалась", "Never opened"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let s = app.size {
                                Text(Fmt.bytes(s)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(app.id)
                    }
                    .scrollContentBackground(.hidden)
                    .overlay { if u.loading { ProgressView() } }
                }
                .frame(width: 340)
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(28)
        .task { await u.load() }
        .confirmationDialog(T("Видалити «\(u.selected?.name ?? "")»?", "Uninstall “\(u.selected?.name ?? "")”?"), isPresented: $confirm) {
            Button(T("Перемістити в Кошик", "Move to Trash"), role: .destructive) { Task { await u.uninstall() } }
        } message: {
            Text(T("Програму буде закрито, а обрані файли (\(Fmt.bytes(u.leftoversSize))) переміщено в Кошик.", "The app will be quit and the selected files (\(Fmt.bytes(u.leftoversSize))) moved to the Trash."))
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = u.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Image(nsImage: Icons.icon(app.id)).resizable().frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.title.bold())
                            Text("\(app.bundleID)" + (app.version.isEmpty ? "" : " · v\(app.version)"))
                                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            if let d = app.lastUsed {
                                Text(T("Востаннє відкривалась ", "Last opened ") + Fmt.relative(d)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Fmt.bytes(u.leftoversSize)).font(.system(size: 28, weight: .heavy, design: .rounded))
                                .contentTransition(.numericText())
                            Text(T("буде звільнено", "will be freed")).foregroundStyle(.secondary).font(.caption)
                        }
                        Spacer()
                        if u.working { ProgressView().controlSize(.small) }
                        Button { confirm = true } label: {
                            Label(T("Видалити", "Uninstall"), systemImage: "trash").font(.headline).padding(.horizontal, 8).padding(.vertical, 3)
                        }
                        .buttonStyle(.glassProminent).tint(.red).controlSize(.large)
                        .disabled(u.working || u.leftoversSize == 0)
                    }
                    if let m = u.message {
                        Label(m, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    VStack(spacing: 4) {
                        if u.findingLeftovers {
                            HStack { ProgressView().controlSize(.small); Text(T("Шукаю залишки…", "Looking for leftovers…")).foregroundStyle(.secondary) }
                                .padding()
                        }
                        ForEach(u.leftovers) { l in
                            HStack(spacing: 10) {
                                CheckButton(state: l.selected ? .on : .off, tint: .teal) { u.toggle(l.id) }
                                Image(nsImage: Icons.icon(l.id)).resizable().frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(l.label).fontWeight(.medium)
                                    Text(Fmt.path(l.id)).font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(Fmt.bytes(l.size)).monospacedDigit()
                                Button { reveal(l.id) } label: { Image(systemName: "arrow.right.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                    }
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
                .padding(22)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            GlassCard(radius: 24) {
                EmptyState(symbol: "square.grid.2x2", title: T("Оберіть програму", "Choose an app"),
                           text: T("Void знайде її дані, кеші, налаштування й контейнери, щоб не лишилося сміття.", "Void finds its data, caches, preferences and containers so nothing is left behind."), tint: .teal)
            }
        }
    }
}

// MARK: - Optimizer

struct OptimizeView: View {
    @Environment(Optimizer.self) private var o

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .optimize, subtitle: T("Швидкі службові дії. Позначені 🔒 попросять пароль адміністратора", "Quick maintenance tasks. Ones marked 🔒 ask for an admin password"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(o.actions) { a in card(a) }
                }
            }
            .padding(28)
        }
    }

    private func card(_ a: OptAction) -> some View {
        let st = o.status[a.id] ?? .idle
        return GlassCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: a.symbol, tint: a.tint, size: 38)
                    Spacer()
                    if a.admin { Image(systemName: "lock.fill").foregroundStyle(.tertiary) }
                }
                Text(a.title.s).font(.headline)
                Text(a.detail.s).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 36, alignment: .top)
                HStack {
                    switch st {
                    case .idle: EmptyView()
                    case .running: ProgressView().controlSize(.small)
                    case .ok(let m): Label(m, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    case .fail(let m): Label(m, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).lineLimit(1)
                    }
                    Spacer()
                    Button(T("Виконати", "Run")) { Task { await o.run(a) } }
                        .buttonStyle(.glass)
                        .disabled(st == .running)
                }
            }
        }
    }
}
