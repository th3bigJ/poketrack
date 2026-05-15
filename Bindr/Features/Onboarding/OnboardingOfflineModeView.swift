import SwiftUI

// MARK: - OnboardingOfflineModeView
//
// Step 2 of `BindrOnboardingFlow`. Pitches the offline collection pack
// (Wi-Fi-only download of every catalog image for the selected brand) as
// "your binder travels with you".
//
// The actual offline-pack download isn't kicked off here — we only mark
// the toggle preference on `services.offlineImageSettings`. The catalog
// pipeline (post-onboarding) reads that flag and schedules the pack
// download on the next Wi-Fi window. This matches the existing settings
// flow so the user can change their mind later in Account.
//
// Visual story: a "device" mockup at top swaps between a green online
// pill and a violet offline pill on a loop, so the user reads the value
// proposition without having to read.

struct OnboardingOfflineModeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let brand: TCGBrand
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var enableOffline: Bool = true
    @State private var animatePhase: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    headline
                    deviceMockup
                    pillarsBlock
                    toggleBlock
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            ctaRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animatePhase.toggle()
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text("Built to go\nanywhere.")
                .font(.system(size: 36, weight: .heavy))
                .lineSpacing(-2)
            Text("Premium binders, a full deck builder, and offline access — the complete toolkit for your collection.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Device mockup

    private var deviceMockup: some View {
        ZStack {
            // Backdrop glow
            RadialGradient(
                colors: [accent.opacity(colorScheme == .dark ? 0.32 : 0.20), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 200
            )
            .blur(radius: 24)
            .frame(height: 260)

            VStack(spacing: 0) {
                // Top notch / status bar
                HStack {
                    Text("6:22")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: animatePhase ? "wifi.slash" : "wifi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(animatePhase ? BindrPalette.wishlistViolet : BindrPalette.ownedGreen)
                            .contentTransition(.symbolEffect(.replace))
                        Image(systemName: "battery.100")
                            .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, BindrSpacing.md)
                .padding(.vertical, BindrSpacing.sm)
                .foregroundStyle(.primary)

                // Pill connection state
                HStack(spacing: 6) {
                    Circle()
                        .fill(animatePhase ? BindrPalette.wishlistViolet : BindrPalette.ownedGreen)
                        .frame(width: 7, height: 7)
                    Text(animatePhase ? "OFFLINE · Browsing from pack" : "ONLINE · Live catalog")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill((animatePhase ? BindrPalette.wishlistViolet : BindrPalette.ownedGreen).opacity(0.16))
                }
                .padding(.vertical, BindrSpacing.sm)

                // Sample features grid
                HStack(spacing: 8) {
                    miniCard(index: 0)
                    miniBinder()
                    miniDeck()
                }
                .padding(.horizontal, BindrSpacing.md)
                .padding(.bottom, BindrSpacing.md)

                // Scan progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Catalog pack")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text(animatePhase ? "100%" : "67%")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, BindrPalette.ownedGreen],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * (animatePhase ? 1.0 : 0.67))
                            }
                            .frame(height: 4)
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal, BindrSpacing.md)
                .padding(.bottom, BindrSpacing.md)
            }
            .frame(maxWidth: 280)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.18), radius: 28, x: 0, y: 14)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniCard(index: Int) -> some View {
        let pair = (Color(hex: "EF1F2F"), Color(hex: "7B0E18"))
        return ZStack {
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [pair.0, pair.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                .padding(0.5)
            VStack(alignment: .leading) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("PULL")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(6)
        }
        .aspectRatio(0.7, contentMode: .fit)
    }

    private func miniBinder() -> some View {
        let pair = (Color(hex: "2A1A4A"), Color(hex: "0A0518"))
        return ZStack {
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [pair.0, pair.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                .padding(0.5)
            VStack(alignment: .center) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BindrPalette.binderGold)
                Spacer()
                Text("BINDER")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(6)
        }
        .aspectRatio(0.7, contentMode: .fit)
    }

    private func miniDeck() -> some View {
        let pair = (Color(hex: "FF7A3C"), Color(hex: "C0351F"))
        return ZStack {
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [pair.0, pair.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                .padding(0.5)
            VStack(alignment: .trailing) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("DECK")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(6)
        }
        .aspectRatio(0.7, contentMode: .fit)
    }

    // MARK: Pillars

    private var pillarsBlock: some View {
        VStack(spacing: BindrSpacing.sm) {
            offlineBenefit(
                icon: "books.vertical.fill",
                title: "Digital binders",
                description: "3D embossed covers, custom layouts, and a page worth showing off.",
                tint: BindrPalette.binderGold
            )
            offlineBenefit(
                icon: "rectangle.stack.badge.plus",
                title: "Deck builder",
                description: "Import from PTCGL or build from scratch. Real-time legality, no compromises.",
                tint: BindrPalette.deckBlue
            )
            offlineBenefit(
                icon: "wifi.slash",
                title: "Works offline",
                description: "Scanner, catalog, and binder all keep going without a signal.",
                tint: accent
            )
            offlineBenefit(
                icon: "lock.shield.fill",
                title: "Wi-Fi only by default",
                description: "Image packs never touch your cellular data unless you say so.",
                tint: BindrPalette.ownedGreen
            )
        }
    }

    private func offlineBenefit(icon: String, title: String, description: String, tint: Color) -> some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.14))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }

    // MARK: Toggle

    private var toggleBlock: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $enableOffline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download \(brand.displayTitle) pack")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(OfflinePackDownloadSizeCopy.approximateLabel(for: brand)) · Wi-Fi only")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)
            .padding(BindrSpacing.md)
            .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
        }
    }

    // MARK: CTA

    private var ctaRow: some View {
        VStack(spacing: BindrSpacing.sm) {
            Button {
                Haptics.lightImpact()
                services.offlineImageSettings.setOfflinePackEnabled(enableOffline, for: brand)
                onContinue()
            } label: {
                HStack(spacing: 8) {
                    Text(enableOffline ? "Enable & Continue" : "Continue")
                        .font(.system(size: 17, weight: .heavy))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.55 : 0.32), radius: 22, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, BindrSpacing.lg)

            Button {
                Haptics.lightImpact()
                onSkip()
            } label: {
                Text("Not now")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding(.bottom, BindrSpacing.lg)
        }
        .padding(.top, BindrSpacing.sm)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(uiColor: .systemBackground).opacity(0.65),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
