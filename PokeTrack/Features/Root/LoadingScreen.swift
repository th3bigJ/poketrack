import SwiftUI
import UIKit

struct LoadingScreen: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image("pokeball")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }

                Text("Finishing catching Pokémon,\nplease wait…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
