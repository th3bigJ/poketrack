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
            
            // Use the first Pokémon's name or a generic name for the deck
            let deckTitle = lines.first(where: { !$0.name.contains("Energy") })?.name ?? "Imported Deck"
            let deck = Deck(title: "Imported \(deckTitle)", brand: .pokemon, format: .pokemonStandard)
            
            var deckCards: [DeckCard] = []
            let allSets = await services.cardData.catalogSets(for: .pokemon)
            
            for line in lines {
                var foundCard: Card? = nil
                
                // 1. Find the set by its PTCGL code (uppercase)
                let targetSet = allSets.first { 
                    $0.code?.uppercased() == line.setCode.uppercased() || 
                    $0.setCode.uppercased() == line.setCode.uppercased() 
                }
                
                if let foundSet = targetSet {
                    // 2. Load cards for that set
                    let setCards = await services.cardData.loadCards(forSetCode: foundSet.setCode)
                    
                    // 3. Find card by number (strip leading zeros if needed)
                    let normalizedNum = line.cardNumber.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                    foundCard = setCards.first { 
                        $0.cardNumber == line.cardNumber || 
                        $0.cardNumber == normalizedNum ||
                        $0.printedNumber == line.cardNumber
                    }
                    
                    if foundCard == nil {
                        // Fallback 1: search by name in that set if number fails
                        foundCard = setCards.first { $0.cardName.lowercased() == line.name.lowercased() }
                    }
                }
                
                if foundCard == nil {
                    // Fallback 2: Global search by name and number if set code matching failed or card not in set
                    let normalizedNum = line.cardNumber.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                    let searchResults = await services.cardData.searchByName(query: line.name, catalogBrand: .pokemon)
                    foundCard = searchResults.first { 
                        $0.cardNumber == line.cardNumber || 
                        $0.cardNumber == normalizedNum ||
                        $0.printedNumber == line.cardNumber
                    }
                }
                
                if let card = foundCard {
                    let deckCard = DeckCard(
                        cardID: card.masterCardId,
                        variantKey: "normal", 
                        cardName: card.cardName,
                        quantity: line.quantity,
                        isBasicEnergy: card.category?.lowercased() == "energy" && card.subtype?.lowercased() == "basic",
                        isAceSpec: card.subtype?.lowercased().contains("ace spec") == true,
                        isRadiant: card.subtype?.lowercased().contains("radiant") == true,
                        isBasicPokemon: card.stage?.lowercased() == "basic",
                        isRuleBox: card.subtypes?.contains(where: { ["ex", "v", "vmax", "vstar", "gx"].contains($0.lowercased()) }) == true,
                        setKey: card.setCode,
                        regulationMark: card.regulationMark,
                        elementTypes: card.elementTypes,
                        trainerType: card.trainerType,
                        isEnergy: card.category?.lowercased() == "energy",
                        imageLowSrc: card.imageLowSrc,
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
            
            // Add cards to deck
            deck.cards = deckCards
            modelContext.insert(deck)
            
            isImporting = false
            dismiss()
        }
    }
}
