import SwiftUI

struct CleanView: View {
    @Environment(Cleaner.self) private var cleaner
    @Environment(SystemMonitor.self) private var system
    @State private var confirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(pane: .clean, subtitle: T("Кеші, логи, сміття розробника, інсталятори та Кошик", "Caches, logs, developer junk, installers and Trash")) {
                    if cleaner.phase == .ready {
                        Button(T("Сканувати знову", "Rescan"), systemImage: "arrow.clockwise") { Task { await cleaner.scan() } }
                            .buttonStyle(.glass)
                    }
                }
                if !cleaner.hasFullDiskAccess { FDABanner() }

                switch cleaner.phase {
                case .idle: idle
                case .scanning, .ready: summary; list
                case .cleaning: cleaning
                case .done(let freed, let failed): done(freed, failed)
                }
            }
            .padding(28)
        }
        .task {
            if UserDefaults.standard.bool(forKey: "autoscan"), cleaner.phase == .idle { await cleaner.scan() }
        }
        .confirmationDialog(T("Очистити ", "Clean ") + Fmt.bytes(cleaner.selectedSize) + "?", isPresented: $confirm) {
            Button(T("Очистити", "Clean"), role: .destructive) {
                Task {
                    await cleaner.clean()
                    system.refreshDisk()
                }
            }
        } message: {
            Text(T("Буде оброблено \(cleaner.selectedCount) об'єктів. Кеші та логи видаляються остаточно, інсталятори переносяться в Кошик.", "\(cleaner.selectedCount) items will be processed. Caches and logs are deleted permanently, installers go to the Trash."))
        }
    }

    private var idle: some View {
        GlassCard(padding: 40, radius: 30) {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [.pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.bounce, options: .repeating.speed(0.3))
                Text(T("Розумне очищення", "Smart Cleanup")).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(T("Void перевірить \(CleanCatalog.all.count) категорій і покаже, що можна безпечно видалити. Нічого не зникне без вашого підтвердження.", "Void checks \(CleanCatalog.all.count) categories and shows what can be safely removed. Nothing is deleted without your confirmation."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
                Button {
                    Task { await cleaner.scan() }
                } label: {
                    Label(T("Сканувати", "Scan"), systemImage: "sparkle.magnifyingglass").font(.title3.bold())
                        .padding(.horizontal, 18).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(.pink).controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var summary: some View {
        GlassCard(padding: 22, radius: 26) {
            HStack(spacing: 22) {
                ZStack {
                    Ring(value: cleaner.phase == .scanning ? cleaner.progress : 1, colors: [.pink, .purple], width: 10)
                    if cleaner.phase == .scanning {
                        Text(Fmt.percent(cleaner.progress)).font(.headline.monospacedDigit())
                    } else {
                        Image(systemName: "checkmark").font(.title.bold()).foregroundStyle(.pink)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cleaner.phase == .scanning ? T("Сканування…", "Scanning…") : T("Знайдено ", "Found ") + Fmt.bytes(cleaner.total))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(cleaner.phase == .scanning ? cleaner.currentStep : T("Обрано \(Fmt.bytes(cleaner.selectedSize)) · \(cleaner.selectedCount) об'єктів", "Selected \(Fmt.bytes(cleaner.selectedSize)) · \(cleaner.selectedCount) items"))
                        .foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                if cleaner.phase == .ready {
                    Menu {
                        Button(T("Обрати все", "Select all")) { cleaner.selectAll(true) }
                        Button(T("Зняти все", "Deselect all")) { cleaner.selectAll(false) }
                    } label: { Image(systemName: "checklist") }
                        .menuStyle(.button).buttonStyle(.glass).fixedSize()
                    Button {
                        confirm = true
                    } label: {
                        Label(T("Очистити", "Clean"), systemImage: "trash").font(.headline).padding(.horizontal, 8).padding(.vertical, 3)
                    }
                    .buttonStyle(.glassProminent).tint(.pink).controlSize(.large)
                    .disabled(cleaner.selectedSize == 0)
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 12) {
            ForEach(cleaner.categories) { cat in
                CategoryCard(cat: cat)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
            if cleaner.phase == .ready && cleaner.categories.isEmpty {
                EmptyState(symbol: "checkmark.seal.fill", title: T("Чисто!", "All clean!"), text: T("Нічого вартого видалення не знайдено.", "Nothing worth removing was found."), tint: .green)
            }
        }
    }

    private var cleaning: some View {
        GlassCard(padding: 40, radius: 30) {
            VStack(spacing: 18) {
                ZStack {
                    Ring(value: cleaner.progress, colors: [.pink, .purple], width: 14)
                    Text(Fmt.percent(cleaner.progress)).font(.title.bold().monospacedDigit())
                }
                .frame(width: 140, height: 140)
                Text(T("Очищення…", "Cleaning…")).font(.title2.bold())
                Text(cleaner.currentStep).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func done(_ freed: Int64, _ failed: Int) -> some View {
        GlassCard(padding: 40, radius: 30) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.green.gradient)
                    .symbolEffect(.bounce, value: freed)
                Text(T("Звільнено ", "Freed ") + Fmt.bytes(freed))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                Text(T("Тепер вільно ", "Now free: ") + Fmt.bytes(system.diskFree) + (failed > 0 ? T(" · \(failed) об'єктів зайняті системою і пропущені", " · \(failed) items in use were skipped") : ""))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(T("Готово", "Done")) { cleaner.reset() }.buttonStyle(.glass)
                    Button(T("Сканувати знову", "Rescan")) { Task { await cleaner.scan() } }.buttonStyle(.glassProminent).tint(.pink)
                }
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct CategoryCard: View {
    let cat: CleanCategory
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CheckButton(state: cat.state, tint: cat.def.tint) { cleaner.toggle(category: cat.id) }
                IconTile(symbol: cat.def.symbol, tint: cat.def.tint, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.def.title.s).font(.headline)
                    Text(cat.def.subtitle.s + " · \(cat.items.count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.bytes(cat.selectedSize))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(cat.state == .off ? .secondary : .primary)
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(cat.expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { cleaner.toggleExpanded(cat.id) }

            if cat.expanded {
                Divider().padding(.vertical, 10)
                let maxSize = cat.items.first?.size ?? 1
                LazyVStack(spacing: 6) {
                    ForEach(cat.items.prefix(300)) { item in
                        HStack(spacing: 10) {
                            CheckButton(state: item.selected ? .on : .off, tint: cat.def.tint) {
                                cleaner.toggle(item: item.id, in: cat.id)
                            }
                            .font(.body)
                            Image(nsImage: Icons.icon(item.url)).resizable().frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).lineLimit(1)
                                Text(Fmt.path(item.url)).font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            SizeBar(fraction: Double(item.size) / Double(max(maxSize, 1)), tint: cat.def.tint)
                                .frame(width: 80)
                            Text(Fmt.bytes(item.size)).font(.callout.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                            Button { reveal(item.url) } label: { Image(systemName: "arrow.right.circle") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help(T("Показати у Finder", "Show in Finder"))
                        }
                        .padding(.leading, 4)
                    }
                    if cat.items.count > 300 {
                        Text(T("…та ще ", "…and ") + "\(cat.items.count - 300)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
