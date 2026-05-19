import SwiftUI
import UserNotifications

// MARK: - OnboardingNotificationsView
//
// Step 4 of `BindrOnboardingFlow`. Pitches notification value before
// requesting iOS permission — wishlist alerts, price drops, trade offers,
// and new set drops. The native permission prompt fires when the user taps
// "Enable Alerts"; "Not now" advances without requesting permission.
// Either way `onContinue` is called to move on to the Premium step.

struct OnboardingNotificationsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    headline
                    notificationPeeks
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            ctaRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text("Stay in\nthe loop.")
                .font(.system(size: 36, weight: .heavy))
                .lineSpacing(-2)
            Text("Get notified the moment something relevant to your collection happens — wishlist matches, price swings, and more.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Notification peeks

    private var notificationPeeks: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "WHAT YOU'LL HEAR ABOUT")

            VStack(spacing: BindrSpacing.sm) {
                peekRow(
                    icon: "star.fill",
                    title: "Wishlist alerts",
                    description: "Someone lists a card you want for trade.",
                    tint: BindrPalette.binderGold
                )
                peekRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Price movements",
                    description: "Cards in your collection spike or dip.",
                    tint: BindrPalette.ownedGreen
                )
                peekRow(
                    icon: "arrow.left.arrow.right",
                    title: "Trade offers",
                    description: "New offers and replies on your trade listings.",
                    tint: BindrPalette.deckBlue
                )
                peekRow(
                    icon: "sparkles",
                    title: "New set drops",
                    description: "Be first to know when a new set hits the catalog.",
                    tint: BindrPalette.wishlistViolet
                )
            }
        }
    }

    private func peekRow(icon: String, title: String, description: String, tint: Color) -> some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.16))
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

    // MARK: CTA

    private var ctaRow: some View {
        VStack(spacing: BindrSpacing.sm) {
            Button {
                Haptics.lightImpact()
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                    DispatchQueue.main.async { onContinue() }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Enable Alerts")
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
                onContinue()
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
