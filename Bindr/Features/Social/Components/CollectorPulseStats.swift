import SwiftUI

// MARK: - CollectorPulseStats
//
// Small horizontal stat strip placed under the Social landing hero —
// "47K Trainers • 1.2K trades today • 312 grails moving". Numbers are
// placeholder fixtures; once the Social API has real aggregate counts
// this view can be re-pointed at them without touching call sites.
//
// Visual contract: numbers in a heavy display weight, label below in a
// muted caption, vertical dividers between cells. Lives flush inside a
// glass tile so it reads as a "live community pulse" panel, not three
// random stats floating in space.

struct CollectorPulseStats: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    struct Stat: Identifiable, Hashable {
        let id = UUID()
        let value: String
        let label: String
        let trend: String?
    }

    let stats: [Stat]

    init(stats: [Stat] = .defaultPulse) {
        self.stats = stats
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                VStack(spacing: 4) {
                    Text(stat.value)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(stat.label)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    if let trend = stat.trend {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(trend)
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(BindrPalette.ownedGreen)
                    }
                }
                .frame(maxWidth: .infinity)

                if index < stats.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.10))
                        .frame(width: 0.5, height: 36)
                }
            }
        }
        .padding(.vertical, BindrSpacing.md)
        .padding(.horizontal, BindrSpacing.lg)
        .frame(maxWidth: .infinity)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }
}

extension Array where Element == CollectorPulseStats.Stat {
    static let defaultPulse: [CollectorPulseStats.Stat] = [
        .init(value: "47K",  label: "TRAINERS",  trend: "+312"),
        .init(value: "1.2K", label: "TRADES TODAY", trend: nil),
        .init(value: "312",  label: "GRAILS LIVE", trend: "+18")
    ]
}
