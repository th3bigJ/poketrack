import SwiftUI

struct DashboardProgressRingTile: View {
    let snapshot: DashboardProgressSnapshot
    let accentColor: Color
    var onRemove: (() -> Void)? = nil

    private let tileWidth: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            progressArtwork
                .frame(height: 48)
                .frame(maxWidth: .infinity)

            Text(snapshot.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                        Capsule(style: .continuous)
                            .fill(accentColor)
                            .frame(width: max(geo.size.width * snapshot.progress, snapshot.progress > 0 ? 4 : 0))
                    }
                }
                .frame(height: 5)

                Text("\(Int(snapshot.progress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            Text("\(snapshot.collected) / \(snapshot.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .frame(width: tileWidth, alignment: .leading)
        .glassInsetStyle(cornerRadius: 16)
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
                progressArtworkPlaceholder(showSpinner: true)
            }
            .id(url.absoluteString)
        } else {
            progressArtworkPlaceholder(showSpinner: false)
        }
    }

    private func progressArtworkPlaceholder(showSpinner: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            if showSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(accentColor)
            } else {
                Image(systemName: snapshot.kind == .pokemon ? "hare.fill" : "square.stack.3d.up.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
