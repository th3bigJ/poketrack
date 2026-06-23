import SwiftUI

struct DashboardProgressRingTile: View {
    let snapshot: DashboardProgressSnapshot
    let accentColor: Color
    let colorScheme: ColorScheme
    var onRemove: (() -> Void)? = nil

    private let ringDiameter: CGFloat = 124
    private let ringLineWidth: CGFloat = 5
    private let artworkSize: CGFloat = 56

    private var trackColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: ringLineWidth)

                Circle()
                    .trim(from: 0, to: max(snapshot.progress, 0.001))
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accentColor.opacity(0.28), radius: 3, x: 0, y: 1)

                VStack(spacing: 5) {
                    progressArtwork
                        .frame(width: artworkSize, height: artworkSize)

                    Text(snapshot.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)

                    Text(snapshot.modeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(snapshot.collected) / \(snapshot.total)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text("\(Int(snapshot.progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .frame(width: ringDiameter, height: ringDiameter)
        }
        .frame(width: ringDiameter)
        .contextMenu {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Stop Tracking", systemImage: "xmark.circle")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.title), \(snapshot.modeLabel), \(snapshot.collected) of \(snapshot.total), \(Int(snapshot.progress * 100)) percent")
    }

    @ViewBuilder
    private var progressArtwork: some View {
        if let url = snapshot.artworkURL {
            CachedAsyncImage(url: url, targetSize: CGSize(width: 112, height: 112)) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Color.primary.opacity(0.06)
            }
        } else {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
