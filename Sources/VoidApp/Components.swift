import SwiftUI

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.15), tint.mix(with: .black, by: 0.2)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.35), radius: 5, y: 2)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var radius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

struct Ring: View {
    var value: Double
    var colors: [Color]
    var width: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.002, min(value, 1)))
                .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.last ?? .blue).opacity(0.35), radius: 6)
        }
        .animation(.smooth(duration: 0.6), value: value)
    }
}

struct Sparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = w / CGFloat(max(values.count - 1, 1))
            let pts = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: h * (1 - CGFloat(min(max(v, 0), 1))))
            }
            ZStack {
                Path { p in
                    guard let f = pts.first, let l = pts.last else { return }
                    p.move(to: CGPoint(x: f.x, y: h))
                    p.addLines(pts)
                    p.addLine(to: CGPoint(x: l.x, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(pts) }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct Backdrop: View {
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let a = scheme == .dark ? 0.32 : 0.22
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: [
                tint.opacity(a), .clear, .purple.opacity(a * 0.6),
                .clear, tint.opacity(a * 0.25), .clear,
                .cyan.opacity(a * 0.5), .clear, tint.opacity(a * 0.7),
            ]
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.8), value: tint)
    }
}

struct PageHeader<Trailing: View>: View {
    let pane: Pane
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: pane.symbol, tint: pane.tint, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(pane: Pane, subtitle: String) { self.init(pane: pane, subtitle: subtitle) { EmptyView() } }
}

enum CheckState { case on, off, mixed }

struct CheckButton: View {
    var state: CheckState
    var tint: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.circle.fill" : state == .mixed ? "minus.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(state == .off ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

struct SizeBar: View {
    var fraction: Double
    var tint: Color
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.primary.opacity(0.07))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint.gradient)
                        .frame(width: max(3, g.size.width * min(max(fraction, 0), 1)))
                }
        }
        .frame(height: 6)
    }
}

struct StatLine: View {
    let label: String
    let value: String
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let color { Circle().fill(color).frame(width: 7, height: 7) }
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.callout)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var tint: Color = .secondary
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(tint)
            Text(title).font(.title3.bold())
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct FDABanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(T("Немає повного доступу до диска", "No Full Disk Access")).font(.headline)
                Text(T("Кошик, Пошта та деякі кеші не будуть проскановані. Додайте Void у Приватність → Повний доступ до диска.", "Trash, Mail and some caches can’t be scanned. Add Void in Privacy → Full Disk Access."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(T("Відкрити налаштування", "Open Settings")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.glass)
        }
        .padding(16)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 18))
    }
}
