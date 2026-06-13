import SwiftUI

/// Full BindR brand mark (card art + wordmark + tagline) from the asset catalog.
struct BindrBrandLogoView: View {
    var maxWidth: CGFloat = 280
    /// The artwork ships on black; a matching backdrop keeps it crisp in light mode.
    var showsDarkBackdrop: Bool = true

    var body: some View {
        Group {
            if showsDarkBackdrop {
                logoImage
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black)
                    }
            } else {
                logoImage
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BindR")
    }

    private var logoImage: some View {
        Image("BindrBrandLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
    }
}
