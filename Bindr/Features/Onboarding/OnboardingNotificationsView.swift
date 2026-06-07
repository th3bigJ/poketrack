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

                            // Check current status off the main actor — UNC initialization
                            // can be slow and would hitch the UI if run on MainActor.
                            let status = await Task.detached(priority: .userInitiated) {
                                await center.notificationSettings().authorizationStatus
                            }.value

                            if status == .denied {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    await UIApplication.shared.open(url)
                                }
                            } else if status == .notDetermined {
                                // requestAuthorization suspends until the user responds to
                                // the system dialog — run off main so the animation thread
                                // stays unblocked during that wait.
                                let granted = await Task.detached(priority: .userInitiated) {
                                    (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                                }.value
                                if granted {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            } else {
                                UIApplication.shared.registerForRemoteNotifications()
                            }

                            await services.socialPush.refreshAuthorizationStatus()
                            onContinue()
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
                description: "New offers and replies for cards you have marked available."
            )
            OnboardingFeatureRow(
                icon: "sparkles",
                title: "New set drops",
                description: "Be first to know when a new set hits the catalog."
            )
        }
    }
}
