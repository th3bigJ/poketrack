import SwiftUI
import UIKit

struct OfficialDeckListSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.dismiss) private var dismiss

    let deck: Deck

    @State private var playerName = ""
    @State private var playerID = ""
    @State private var birthdate = Date()
    @State private var division: OfficialDeckListDivision = .masters
    @AppStorage(OfficialDeckListPlayerInfoStore.rememberPreferenceKey)
    private var savePlayerInfoForFuture = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedPDFURL: URL?
    @State private var showShareSheet = false

    private var canGenerate: Bool {
        !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !playerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !deck.cardList.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Player Name", text: $playerName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    TextField("Player ID", text: $playerID)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    DatePicker("Birthdate", selection: $birthdate, displayedComponents: .date)
                } header: {
                    Text("Player Information")
                }

                Section {
                    LabeledContent("Format", value: deck.deckFormat.displayName)
                } footer: {
                    Text("Format is set from this deck’s type in Deck Builder.")
                        .font(.caption)
                }

                Section {
                    ForEach(OfficialDeckListDivision.allCases) { option in
                        Button {
                            division = option
                            HapticManager.selection()
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: division == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(division == option ? Color.accentColor : Color.secondary)
                                    .imageScale(.large)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(division == option ? .isSelected : [])
                    }
                } header: {
                    Text("Division")
                } footer: {
                    Text("Select one division for tournament deck registration.")
                        .font(.caption)
                }

                if deck.cardList.isEmpty {
                    Section {
                        Text("Add cards to this deck before generating a deck list.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle("Save player information for future deck lists", isOn: $savePlayerInfoForFuture)
                        .tint(accent)
                }
            }
            .onAppear(perform: loadSavedPlayerInfoIfNeeded)
            .navigationTitle("Create Deck List")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await generatePDF() }
                    }
                    .foregroundStyle(.primary)
                    .disabled(!canGenerate || isGenerating)
                }
            }
            .overlay {
                if isGenerating {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("Building PDF…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: { generatedPDFURL = nil }) {
                if let url = generatedPDFURL {
                    ShareSheet(items: [url]) { completed in
                        if completed {
                            showShareSheet = false
                            generatedPDFURL = nil
                            dismiss()
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func loadSavedPlayerInfoIfNeeded() {
        guard let saved = OfficialDeckListPlayerInfoStore.loadPlayerInfo() else { return }
        playerName = saved.playerName
        playerID = saved.playerID
        birthdate = saved.birthdate
        division = saved.division
    }

    private func persistPlayerInfoPreference(_ info: OfficialDeckListPlayerInfo) {
        if savePlayerInfoForFuture {
            OfficialDeckListPlayerInfoStore.savePlayerInfo(info)
        } else {
            OfficialDeckListPlayerInfoStore.clearPlayerInfo()
        }
    }

    private func generatePDF() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let idsNeedingLookup = deck.cardList
            .filter { ($0.localId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.cardID)

        var pokemonSets = await services.cardData.catalogSets(for: .pokemon)
        let hasAnySetAbbreviation = pokemonSets.contains {
            guard let abbr = $0.setAbbreviation else { return false }
            return !abbr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if pokemonSets.isEmpty || !hasAnySetAbbreviation {
            await services.forceCatalogRedownloadFromSettings()
            pokemonSets = await services.cardData.catalogSets(for: .pokemon)
        }

        let lookedUpCards = await services.cardData.loadCards(
            masterCardIDs: idsNeedingLookup,
            catalogBrand: .pokemon
        )
        let cardsByMasterId = Dictionary(uniqueKeysWithValues: lookedUpCards.map { ($0.masterCardId, $0) })
        let deckListBody = PTCGLService.shared.exportToPTCGL(
            deck: deck,
            sets: pokemonSets,
            cardsByMasterId: cardsByMasterId
        )

        let playerInfo = OfficialDeckListPlayerInfo(
            playerName: playerName,
            playerID: playerID,
            birthdate: birthdate,
            division: division
        )

        do {
            let data = try OfficialDeckListPDFService.generatePDF(
                playerInfo: playerInfo,
                formatDisplayName: deck.deckFormat.displayName,
                deckListBody: deckListBody
            )
            let url = try OfficialDeckListPDFService.writeTemporaryPDF(data: data, playerName: playerName)
            persistPlayerInfoPreference(playerInfo)
            generatedPDFURL = url
            HapticManager.notification(.success)
            showShareSheet = true
        } catch {
            errorMessage = "Could not create the PDF. Please try again."
            HapticManager.notification(.error)
        }
    }
}
