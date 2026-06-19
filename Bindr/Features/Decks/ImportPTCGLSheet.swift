import SwiftUI
import SwiftData

struct ImportPTCGLSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var decklistText = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importedDeck: Deck?
    @State private var pendingDeckCards: [DeckCard] = []
    @State private var pendingDeckName: String = ""
    @State private var showingNamePrompt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isImporting {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Searching for cards...")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = importError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text("Import Error")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            importError = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Paste your exported decklist from TCG Live below:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        TextEditor(text: $decklistText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .overlay(alignment: .topLeading) {
                                if decklistText.isEmpty {
                                    Text("1 Pikachu PGO 27...")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 25)
                                        .padding(.vertical, 24)
                                        .allowsHitTesting(false)
                                }
                            }
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Import from TCG Live")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Name Your Deck", isPresented: $showingNamePrompt) {
                TextField("Deck name", text: $pendingDeckName)
                Button("Cancel", role: .cancel) {
                    pendingDeckCards = []
                    pendingDeckName = ""
                }
                Button("Save") {
                    savePendingDeck()
                }
                .disabled(pendingDeckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Enter a name for the imported deck.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        startImport()
                    }
                    .disabled(decklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                    .bold()
                }
            }
        }
    }

    private func startImport() {
        isImporting = true
        importError = nil
        
        Task {
            let lines = PTCGLService.shared.parseDecklist(decklistText)
            if lines.isEmpty {
                importError = "No valid card lines found. Make sure you copied the export correctly from TCG Live."
                isImporting = false
                return
            }
            
            // Suggest a name from the first non-energy card; user can override in the name prompt
            let deckTitle = lines.first(where: { !$0.name.contains("Energy") })?.name ?? "Imported Deck"
            
            var deckCards: [DeckCard] = []
            let allSets = await services.cardData.catalogSets(for: .pokemon)
            
            for line in lines {
                var foundCard: Card? = nil
                let setToken = line.setCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                
                // 1. Find the set by its TCG Live abbreviation (preferred), then fallback tokens.
                let targetSet = allSets.first { 
                    $0.setAbbreviation?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == setToken ||
                    $0.code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == setToken ||
                    $0.setCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == setToken
                }
                
                if let foundSet = targetSet {
                    // 2. Load cards for that set
                    let setCards = await services.cardData.loadCards(forSetCode: foundSet.setCode)
                    
                    // 3. Find card by number (treat padded and unpadded forms as equivalent).
                    let normalizedNum = normalizedCardToken(line.cardNumber)
                    foundCard = setCards.first { 
                        normalizedCardToken($0.localId ?? "") == normalizedNum ||
                        normalizedCardToken($0.cardNumber) == normalizedNum ||
                        normalizedCardToken($0.printedNumber ?? "") == normalizedNum
                    }
                    
                    if foundCard == nil {
                        // Fallback 1: search by name in that set if number fails
                        let targetName = normalizedPTCGLName(line.name)
                        foundCard = setCards.first { normalizedPTCGLName($0.cardName) == targetName }
                    }
                }
                
                if foundCard == nil {
                    // Fallback 2: Global search by name and number if set code matching failed or card not in set
                    let normalizedNum = normalizedCardToken(line.cardNumber)
                    let searchResults = await services.cardData.searchByName(query: line.name, catalogBrand: .pokemon)
                    foundCard = searchResults.first { 
                        normalizedCardToken($0.localId ?? "") == normalizedNum ||
                        normalizedCardToken($0.cardNumber) == normalizedNum ||
                        normalizedCardToken($0.printedNumber ?? "") == normalizedNum
                    }
                }

                if foundCard == nil,
                   let inferredType = inferredBasicEnergyType(from: line.name) {
                    foundCard = await resolveBasicEnergyFallback(
                        inferredType: inferredType,
                        importedNumberToken: line.cardNumber,
                        allSets: allSets
                    )
                }
                
                if let card = foundCard {
                    let isBasicPokemon = card.category?.lowercased() == "pokémon" && (
                        card.stage?.lowercased() == "basic"
                        || card.subtype?.lowercased().contains("basic") == true
                        || card.subtypes?.contains(where: { $0.lowercased() == "basic" }) == true
                    )
                    let deckCard = DeckCard(
                        cardID: card.masterCardId,
                        variantKey: "normal", 
                        cardName: card.cardName,
                        quantity: line.quantity,
                        isBasicEnergy: card.category?.lowercased() == "energy" && card.subtype?.lowercased() == "basic",
                        isAceSpec: card.subtype?.lowercased().contains("ace spec") == true,
                        isRadiant: card.subtype?.lowercased().contains("radiant") == true,
                        isBasicPokemon: isBasicPokemon,
                        isRuleBox: card.subtypes?.contains(where: { ["ex", "v", "vmax", "vstar", "gx"].contains($0.lowercased()) }) == true,
                        setKey: card.setCode,
                        localId: card.localId ?? card.cardNumber,
                        regulationMark: card.regulationMark,
                        elementTypes: card.elementTypes,
                        trainerType: card.trainerType,
                        isEnergy: card.category?.lowercased() == "energy",
                        imageLowSrc: card.displayImageSrc,
                        catalogCategory: card.category,
                        catalogSubtype: card.subtype,
                        catalogStage: card.stage
                    )
                    deckCards.append(deckCard)
                }
            }
            
            if deckCards.isEmpty {
                importError = "Could not find any of the cards in our database. Check your set codes."
                isImporting = false
                return
            }

            await MainActor.run {
                pendingDeckCards = deckCards
                pendingDeckName = deckTitle
                isImporting = false
                showingNamePrompt = true
            }
        }
    }

    private func savePendingDeck() {
        let name = pendingDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let deck = Deck(title: name, brand: .pokemon, format: .pokemonStandard)
        deck.cards = pendingDeckCards
        modelContext.insert(deck)
        services.scheduleLibraryCloudBackup()
        pendingDeckCards = []
        pendingDeckName = ""
        dismiss()
    }

    private func normalizedPTCGLName(_ raw: String) -> String {
        var out = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        out = out.replacingOccurrences(of: #"\{[a-z]\}"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("basic "), out.hasSuffix(" energy") {
            out = String(out.dropFirst("basic ".count))
        }
        return out
    }

    private func normalizedCardToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let stripped = trimmed.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
        return stripped.isEmpty ? "0" : stripped
    }

    private func inferredBasicEnergyType(from importedName: String) -> String? {
        if let symbolRange = importedName.range(of: #"\{([A-Z])\}"#, options: .regularExpression) {
            let token = String(importedName[symbolRange])
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
                .uppercased()
            switch token {
            case "G": return "Grass"
            case "R": return "Fire"
            case "W": return "Water"
            case "L": return "Lightning"
            case "P": return "Psychic"
            case "F": return "Fighting"
            case "D": return "Darkness"
            case "M": return "Metal"
            case "N": return "Dragon"
            case "Y": return "Fairy"
            case "C": return "Colorless"
            default: break
            }
        }

        let lower = importedName.lowercased()
        if lower.contains("grass") { return "Grass" }
        if lower.contains("fire") { return "Fire" }
        if lower.contains("water") { return "Water" }
        if lower.contains("lightning") { return "Lightning" }
        if lower.contains("psychic") { return "Psychic" }
        if lower.contains("fighting") { return "Fighting" }
        if lower.contains("dark") { return "Darkness" }
        if lower.contains("metal") { return "Metal" }
        if lower.contains("dragon") { return "Dragon" }
        if lower.contains("fairy") { return "Fairy" }
        if lower.contains("colorless") { return "Colorless" }
        return nil
    }

    private func resolveBasicEnergyFallback(
        inferredType: String,
        importedNumberToken: String,
        allSets: [TCGSet]
    ) async -> Card? {
        guard let meeSet = allSets.first(where: {
            $0.setAbbreviation?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "MEE"
            || $0.code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "MEE"
            || $0.setCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "MEE"
        }) else {
            return nil
        }

        let meeCards = await services.cardData.loadCards(forSetCode: meeSet.setCode)
        let normalizedNum = normalizedCardToken(importedNumberToken)

        return meeCards.first {
            ($0.category?.lowercased() == "energy")
            && ($0.energyType?.lowercased() == "basic")
            && ($0.elementTypes?.first?.lowercased() == inferredType.lowercased())
            && (
                normalizedCardToken($0.localId ?? "") == normalizedNum
                || normalizedCardToken($0.cardNumber) == normalizedNum
                || normalizedCardToken($0.printedNumber ?? "") == normalizedNum
            )
        } ?? meeCards.first {
            ($0.category?.lowercased() == "energy")
            && ($0.energyType?.lowercased() == "basic")
            && ($0.elementTypes?.first?.lowercased() == inferredType.lowercased())
        }
    }
}
