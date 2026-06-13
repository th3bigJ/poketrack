import SwiftUI
import UIKit

/// Shown on paywalls in TestFlight builds where real sandbox billing is required.
struct TestFlightSandboxNotice: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Label("TestFlight billing test", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text("TestFlight never charges real money. Subscribe and Restore only work after you sign in with a Sandbox Apple ID:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                noticeStep(1, "In App Store Connect: Users and Access → Sandbox → Testers → create a sandbox tester.")
                noticeStep(2, "On this iPhone: Settings → App Store → Sandbox Account.")
                noticeStep(3, "Sign in with that Sandbox Apple ID, return here, then confirm below.")
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .padding(.top, 2)

            Toggle(isOn: Binding(
                get: { services.store.sandboxSetupAcknowledged },
                set: { services.store.sandboxSetupAcknowledged = $0 }
            )) {
                Text("I've signed into my Sandbox Account")
                    .font(.system(size: 13, weight: .medium))
            }
            .tint(accent)
            .padding(.top, BindrSpacing.xs)
        }
        .padding(BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: BindrRadius.lg, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BindrRadius.lg, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        }
    }

    private func noticeStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: BindrSpacing.sm) {
            Text("\(number).")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
