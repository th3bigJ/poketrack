import SwiftUI

/// Optional payload rendered beneath the BINDR wordmark while the launch
/// catalog pipeline is running. When `nil`, only the wordmark is shown.
struct LaunchProgressState: Equatable {
    var message: String
    var status: String
    var fraction: Double
    var downloadedBytes: Int64
    var totalBytes: Int64
    /// `true` once the catalog reporter has counted real HTTP body bytes —
    /// switches the bar from indeterminate spinner to determinate progress bar.
    var hasByteProgress: Bool
}

/// Launch surface: reveals "BINDR" one character at a time, then optionally
/// keeps the wordmark on screen with a progress bar / status line beneath it
/// while the catalog pipeline finishes. Stays mounted until the parent decides
/// to dismiss — there is no auto-dismiss timer anymore. This is what prevents
/// the dashboard "flash" between wordmark and download UI.
struct LaunchWordmarkView: View {
    /// Optional download status block rendered below the wordmark.
    var progress: LaunchProgressState? = nil
    /// Fired exactly once after the reveal stagger finishes — parent uses this
    /// to gate the minimum on-screen time before dismissing.
    var onRevealComplete: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent
    @State private var animStates: [Bool] = [false, false, false, false, false]
    @State private var wholeWordAnim = false
    @State private var hasStartedAnimation = false
    @State private var hasFiredRevealComplete = false
    @State private var taglineWordStates: [Bool] = [false, false, false]
    private let fullWord = "BINDR"
    private let taglineWords = ["Share", "your", "Collection"]

    private var byteProgressText: String {
        guard let p = progress, p.totalBytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        let downloaded = formatter.string(fromByteCount: p.downloadedBytes)
        let total = formatter.string(fromByteCount: p.totalBytes)
        return "\(downloaded) / \(total) downloaded"
    }

    private var percentText: String {
        guard let p = progress else { return "" }
        return "\(Int((min(max(p.fraction, 0), 1) * 100).rounded()))%"
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                wordmark

                tagline

                // Progress block only appears when a real download is active.
                if progress != nil {
                    progressBlock
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 92)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.28), value: progress != nil)
        }
        .task {
            guard !hasStartedAnimation else { return }
            hasStartedAnimation = true

            // Stagger each character reveal
            for index in 0..<fullWord.count {
                animStates[index] = true
                try? await Task.sleep(nanoseconds: 130_000_000) // 130ms between letters
            }

            // Hold the completed wordmark — let the last spring fully settle
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Gentle breathing pulse — starts only after full settle
            wholeWordAnim = true

            // Stagger in tagline words one at a time
            for index in 0..<taglineWords.count {
                try? await Task.sleep(nanoseconds: 160_000_000) // 160ms between words
                withAnimation(.easeOut(duration: 0.4)) {
                    taglineWordStates[index] = true
                }
            }

            // Brief display before signalling reveal-complete. Parent decides
            // when to actually dismiss; this is just the minimum hold time.
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !hasFiredRevealComplete {
                hasFiredRevealComplete = true
                onRevealComplete()
            }
        }
    }

    private var tagline: some View {
        HStack(spacing: 6) {
            ForEach(0..<taglineWords.count, id: \.self) { index in
                Text(taglineWords[index])
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.50) : Color.black.opacity(0.45))
                    .tracking(1.5)
                    .offset(y: taglineWordStates[index] ? 0 : 6)
                    .opacity(taglineWordStates[index] ? 1 : 0)
            }
        }
    }

    private var wordmark: some View {
        // Static spacing — no layout changes during animation avoids the
        // HStack re-layout thrash that caused the 'R' stutter.
        HStack(spacing: 6) {
            ForEach(0..<fullWord.count, id: \.self) { index in
                Text(String(fullWord[fullWord.index(fullWord.startIndex, offsetBy: index)]))
                    .font(.custom("BebasNeue-Regular", size: 66))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.9))
                    .offset(y: animStates[index] ? 0 : 14)
                    .opacity(animStates[index] ? 1 : 0)
                    .scaleEffect(animStates[index] ? 1 : 0.75)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.75),
                        value: animStates[index]
                    )
            }
        }
        .scaleEffect(wholeWordAnim ? 1.03 : 1.0)
        .animation(
            .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
            value: wholeWordAnim
        )
    }

    @ViewBuilder
    private var progressBlock: some View {
        if let p = progress {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(p.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text(p.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if p.hasByteProgress {
                    VStack(spacing: 6) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .frame(height: 8)
                            Capsule()
                                .fill(bindrAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .mask(alignment: .leading) {
                                    Rectangle()
                                        .frame(maxWidth: .infinity)
                                        .scaleEffect(
                                            x: min(max(p.fraction, 0), 1),
                                            y: 1,
                                            anchor: .leading
                                        )
                                }
                                .animation(.easeOut(duration: 0.18), value: p.fraction)
                        }
                        .frame(height: 8)

                        HStack(spacing: 6) {
                            Text("\(percentText) complete")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                            if !byteProgressText.isEmpty {
                                Text("·")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(byteProgressText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: 320)
                } else {
                    // Indeterminate phase — nothing has been counted in bytes yet
                    // (e.g. resolving ETags, opening connections). A subtle
                    // ProgressView keeps the user oriented without flashing a
                    // fake 0% bar.
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                }
            }
        }
    }
}

/// Indeterminate startup when the catalog is already local and no HTTP body bytes have been counted yet.
struct StartupBusyView: View {
    let message: String
    let status: String

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                ProgressView()
                    .controlSize(.large)
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
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
        }
    }
}

/// Spinner + text on the dimmed overlay used when re-enabling a catalog without a large download.
struct CatalogEnablingBusyView: View {
    let message: String
    let status: String

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            VStack(spacing: 8) {
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 420)
    }
}

struct LoadingScreen: View {
    let message: String
    let status: String
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64

    @Environment(\.bindrAccent) private var bindrAccent

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
                            .fill(bindrAccent)
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
