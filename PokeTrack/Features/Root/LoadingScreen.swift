import SwiftUI

struct LoadingScreen: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                ProgressView()
                    .controlSize(.large)

                Text("Finishing catching Pokémon,\nplease wait…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
