import SwiftUI

// MARK: - Duplicates

struct DuplicatesView: View {
    @Environment(Duplicates.self) private var d

    var body: some View {
        @Bindable var d = d
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .duplicates, subtitle: T("Однакові файли з різними назвами — порівнюємо вміст, а не імена",
                                                          "Identical files under different names — compared by content, not by name"))

                GlassCard(padding: 18, radius: 22) {
                    HStack(spacing: 14) {
                        Menu {
                            Button(T("Домівка", "Home")) { d.root = home }
                            Button(T("Завантаження", "Downloads")) { d.root = home.sub("Downloads") }
                            Button(T("Документи", "Documents")) { d.root = home.sub("Documents") }
                            Button(T("Робочий стіл", "Desktop")) { d.root = home.sub("Desktop") }
                            Button(T("Зображення", "Pictures")) { d.root = home.sub("Pictures") }
                            Divider()
                            Button(T("Обрати теку…", "Choose folder…")) { pick() }
                        } label: { Label(Fmt.path(d.root), systemImage: "folder") }
                            .menuStyle(.button).buttonStyle(.glass).fixedSize()
                        Picker(T("Від", "Min"), selection: $d.minSize) {
                            Text(Fmt.bytes(100_000)).tag(Int64(100_000))
                            Text(Fmt.bytes(1_000_000)).tag(Int64(1_000_000))
                            Text(Fmt.bytes(10_000_000)).tag(Int64(10_000_000))
                            Text(Fmt.bytes(100_000_000)).tag(Int64(100_000_000))
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 320)
                        Spacer()
                        if d.scanning {
                            Text(d.status).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                            ProgressView(value: d.progress).frame(width: 80)
                            Button(T("Стоп", "Stop")) { d.stop() }.buttonStyle(.glass)
                        } else {
                            Button { d.scan() } label: { Label(T("Знайти", "Find"), systemImage: "magnifyingglass").font(.headline) }
                                .buttonStyle(.glassProminent).tint(.mint)
                        }
                    }
                }

                if !d.groups.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(T("Дублікати займають ", "Duplicates waste ") + Fmt.bytes(d.totalWasted)).font(.headline)
                            Text(T("\(d.groups.count) груп · найстаріша копія лишається", "\(d.groups.count) groups · the oldest copy is kept"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(T("У Кошик", "Move to Trash") + " · " + Fmt.bytes(d.selectedSize), systemImage: "trash") { d.trashSelected() }
                            .buttonStyle(.glassProminent).tint(.red)
                            .disabled(d.selectedCount == 0)
                    }
                    .padding(16)
                    .glassEffect(.regular.tint(.mint.opacity(0.1)), in: .rect(cornerRadius: 18))

                    LazyVStack(spacing: 12) {
                        ForEach(d.groups) { g in group(g) }
                    }
                } else if d.hasScanned && !d.scanning {
                    EmptyState(symbol: "checkmark.circle", title: T("Дублікатів немає", "No duplicates"),
                               text: T("У цій теці немає однакових файлів.", "This folder has no identical files."), tint: .green)
                } else if !d.scanning {
                    EmptyState(symbol: "square.on.square", title: T("Пошук дублікатів", "Find duplicates"),
                               text: T("Оберіть теку й мінімальний розмір. Void порівняє файли за SHA‑256.",
                                       "Choose a folder and minimum size. Void compares files by SHA‑256."), tint: .mint)
                }
            }
            .padding(28)
        }
    }

    private func group(_ g: Duplicates.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(nsImage: Icons.icon(g.files[0].id)).resizable().frame(width: 30, height: 30)
                Text(g.files[0].id.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Text("\(g.files.count) × \(Fmt.bytes(g.size))").foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(g.files) { f in
                HStack(spacing: 10) {
                    CheckButton(state: f.selected ? .on : .off, tint: .red) { d.toggle(f.id, in: g.id) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Fmt.path(f.id)).lineLimit(1).truncationMode(.middle)
                        if let m = f.modified {
                            Text(T("змінено ", "modified ") + Fmt.relative(m)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !f.selected {
                        Text(T("лишається", "kept")).font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                            .glassEffect(.regular.tint(.green.opacity(0.25)), in: .capsule)
                    }
                    Button { reveal(f.id) } label: { Image(systemName: "arrow.right.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.leading, 6)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func pick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = d.root
        if p.runModal() == .OK, let u = p.url { d.root = u }
    }
}

// MARK: - Startup items

struct StartupView: View {
    @Environment(StartupItems.self) private var st

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .startup, subtitle: T("Фонові служби, що запускаються разом із Mac. Вимкніть зайві — Mac стартуватиме швидше",
                                                       "Background services that start with your Mac. Turn off the extras for a faster startup")) {
                    Button(T("Об'єкти входу", "Login Items"), systemImage: "person.crop.circle") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .buttonStyle(.glass)
                    Button(T("Оновити", "Refresh"), systemImage: "arrow.clockwise") { Task { await st.load() } }
                        .buttonStyle(.glass)
                }

                if let e = st.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }

                if st.loading && st.items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }

                ForEach(StartupItems.Scope.allCases, id: \.self) { scope in
                    let list = st.items.filter { $0.scope == scope }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(scope.title).font(.title3.bold())
                                Text("\(list.count)").foregroundStyle(.secondary)
                                if scope == .daemon {
                                    Image(systemName: "lock.fill").foregroundStyle(.tertiary).help(T("Потрібен пароль адміністратора", "Requires an admin password"))
                                }
                            }
                            VStack(spacing: 2) {
                                ForEach(list) { item in row(item) }
                            }
                            .padding(8)
                            .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        }
                    }
                }
            }
            .padding(28)
        }
        .task { if st.items.isEmpty { await st.load() } }
    }

    private func row(_ item: StartupItems.Item) -> some View {
        HStack(spacing: 12) {
            Group {
                if let app = item.appURL, FS.exists(app) {
                    Image(nsImage: Icons.icon(app)).resizable()
                } else {
                    Image(systemName: "gearshape.2.fill").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.vendor).fontWeight(.medium)
                    if item.running {
                        Text(T("працює", "running")).font(.caption2).foregroundStyle(.green)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.green.opacity(0.15), in: .capsule)
                    }
                    if item.appURL != nil, !FS.exists(item.appURL!) {
                        Text(T("програму видалено", "app removed")).font(.caption2).foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: .capsule)
                    }
                }
                Text(item.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(Fmt.path(URL(fileURLWithPath: item.program))).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if st.busy.contains(item.id) { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(get: { item.enabled }, set: { v in Task { await st.setEnabled(item, v) } }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
            Menu {
                Button(T("Показати у Finder", "Show in Finder"), systemImage: "folder") { reveal(item.id) }
                Divider()
                Button(T("Видалити агент", "Remove agent"), systemImage: "trash", role: .destructive) {
                    Task { await st.remove(item) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.button).buttonStyle(.plain).fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}
