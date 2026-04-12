import SwiftUI

struct LoadingScreen: View {
    let message: String
    let status: String
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64

    private var percentText: String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    private var byteProgressText: String {
        guard totalBytes > 0 else { return "Calculating download size…" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        let downloaded = formatter.string(fromByteCount: downloadedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(downloaded) / \(total) downloaded"
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(height: 12)

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(maxWidth: .infinity)
                                    .scaleEffect(x: min(max(progress, 0), 1), y: 1, anchor: .leading)
                            }
                    }
                    .frame(width: min(UIScreen.main.bounds.width - 64, 320), height: 12)

                    Text("\(percentText) complete")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(byteProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
        }
    }
}

#Preview {
    LoadingScreen(
        message: "Updating card data, please wait.",
        status: "Refreshing pricing data…",
        progress: 0.42,
        downloadedBytes: 1_200_000,
        totalBytes: 100_000_000
    )
}
