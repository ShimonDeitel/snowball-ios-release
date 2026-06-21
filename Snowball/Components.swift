import SwiftUI

/// A shrinking progress ring — the core visual. Fills clockwise as a debt is paid down.
/// `progress` is 0 (untouched) … 1 (cleared).
struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 120
    var lineWidth: CGFloat = 12
    /// Optional content centered inside the ring.
    var label: AnyView?

    init(progress: Double, size: CGFloat = 120, lineWidth: CGFloat = 12,
         @ViewBuilder label: () -> some View = { EmptyView() }) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
        self.label = AnyView(label())
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.snowAccent.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(Color.snowAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            label
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

/// A small labelled metric tile.
struct MetricTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.snowAccent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.snowCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A selectable strategy chip (Snowball / Avalanche).
struct StrategyChip: View {
    let strategy: PayoffStrategy
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(strategy.title).font(.subheadline.weight(.semibold))
                Text(strategy.subtitle).font(.caption2)
                    .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.snowAccent : Color.snowCard,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strategy-\(strategy.rawValue)")
    }
}

/// A milestone badge — earned when a debt is cleared. Family-friendly, no emojis.
struct MilestoneBadge: View {
    let title: String
    let systemImage: String
    var earned: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(earned ? Color.snowAccent : .secondary)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(earned ? Color.snowAccent.opacity(0.12)
                                          : Color.snowCard)
                )
            Text(title).font(.caption2.weight(.medium))
                .foregroundStyle(earned ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 84)
        .opacity(earned ? 1 : 0.5)
    }
}

/// Wraps UIActivityViewController so Pro users can share a rendered plan summary.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// A short month-year label, e.g. "Mar 2027".
func monthYear(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMM yyyy"
    return f.string(from: date)
}
