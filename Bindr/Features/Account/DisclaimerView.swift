import SwiftUI

struct DisclaimerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Bindr is an independent card scanning, pricing and collection management application. Bindr is not affiliated with, endorsed by, sponsored by, or in any way officially connected with The Pokémon Company International, Nintendo, Creatures Inc., GAME FREAK, Toei Animation Co. Ltd., Eiichiro Oda, Shueisha Inc., Ravensburger AG, or The Walt Disney Company, or any of their subsidiaries or affiliates.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Text("All card names, game names, and associated terminology including Pokémon, One Piece, and Disney Lorcana are the property of their respective trademark holders. Card images displayed within Bindr are used solely for the purposes of card identification, price reference, and personal collection management, and remain the intellectual property of their respective owners.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Text("Bindr does not claim ownership of any card artwork, game assets, or brand materials. Market price data is independently sourced and presented for informational purposes only. Bindr does not guarantee the accuracy of pricing information and accepts no liability for financial decisions made on the basis of data provided within the application.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Text("All trademarks, registered trademarks, product names, and company names or logos mentioned within Bindr are the property of their respective owners.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Legal Disclaimer")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DisclaimerView()
}
