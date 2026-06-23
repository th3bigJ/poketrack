import SwiftUI

struct DashboardProgressRingTile: View {
    let snapshot: DashboardProgressSnapshot
    let accentColor: Color
    var onRemove: (() -> Void)? = nil

    private let tileWidth: CGFloat = 124
    private let artworkSize: CGFloat = 56

    var body: some View {
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
        .padding(.vertical, 10)
        .frame(width: tileWidth)
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
