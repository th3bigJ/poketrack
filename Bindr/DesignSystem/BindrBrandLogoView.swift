import SwiftUI

/// Full BindR brand mark (card art + wordmark + tagline) from the asset catalog.
/// Uses the transparent PNG so it blends with page backgrounds and gradients.
struct BindrBrandLogoView: View {
    var maxWidth: CGFloat = 280

    var body: some View {
        Image("BindrBrandLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel("BindR")
    }
}
