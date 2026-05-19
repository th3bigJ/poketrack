import SwiftUI
import UserNotifications

// MARK: - OnboardingNotificationsView
//
// Step 4. Refactor brief:
//   * Headline drops to .bold; subtitle to standard secondary contrast.
//   * Feature rows use shared `OnboardingFeatureRow` (monochrome accent
//     icons, no pastel tile backdrops).
//   * Primary CTA centred "Enable Alerts" — no trailing arrow.
//
// Persistence: the request is routed through
// `services.socialPush.requestAuthorizationIfNeeded()` so the push
// service's cached `authorizationStatus` updates in lockstep with the
// OS-level grant. Anywhere in the app that reads that status (e.g.
// Account → Notifications) sees the new state immediately, and the
// subsequent `updateRegistrationState()` call kicks off APNS device-token
// registration as soon as the user signs in.

struct OnboardingNotificationsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    OnboardingHeadline(
                        title: "Stay in the loop.",
                        subtitle: "Get notified the moment something relevant to your collection happens — wishlist matches, price swings, and more."
                    )
                    notificationPeeks
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    OnboardingPrimaryButton(title: "Enable Alerts") {
                        Task {
                            let center = UNUserNotificationCenter.current()
                            let settings = await center.notificationSettings()
                            
                            if settings.authorizationStatus == .denied {
                                // If already denied, open iOS system settings directly to Bindr's page
                                if let url = URL(string: UIApplication.openSettingsURLString),
                                   UIApplication.shared.canOpenURL(url) {
                                    await UIApplication.shared.open(url)
                                }
                                onContinue()
                            } else if settings.authorizationStatus == .notDetermined {
                                // If not yet prompted, request permissions
                                let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                                await services.socialPush.refreshAuthorizationStatus()
                                if granted {
                                    // Register with APNs in the background so there is zero main thread lag
                                    Task {
                                        await services.socialPush.updateRegistrationState()
                                    }
                                }
                                onContinue()
                            } else {
                                // If already authorized, register in the background and continue
                                Task {
                                    await services.socialPush.updateRegistrationState()
                                }
                                onContinue()
                            }
                        }
                    }
                },
                secondary: {
                    OnboardingSecondaryLink(title: "Not now", action: onContinue)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notificationPeeks: some View {
        VStack(spacing: BindrSpacing.sm) {
            OnboardingFeatureRow(
                icon: "star",
                title: "Wishlist alerts",
                description: "Someone lists a card you want for trade."
            )
            OnboardingFeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Price movements",
                description: "Cards in your collection spike or dip."
            )
            OnboardingFeatureRow(
                icon: "arrow.left.arrow.right",
                title: "Trade offers",
                description: "New offers and replies on your trade listings."
            )
            OnboardingFeatureRow(
                icon: "sparkles",
                title: "New set drops",
                description: "Be first to know when a new set hits the catalog."
            )
        }
    }
}
