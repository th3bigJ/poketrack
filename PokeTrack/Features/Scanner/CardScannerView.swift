import SwiftData
import SwiftUI

struct CardScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @State private var showPaywall = false
    @State private var showPicker = false
    @State private var pickedImage: UIImage?
    @State private var recognized: [String] = []
    @State private var matches: [Card] = []
    @State private var errorText: String?

    private var useCamera: UIImagePickerController.SourceType {
        UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    }

    var body: some View {
        Group {
            if !services.store.isPremium {
                ContentUnavailableView(
                    "Premium only",
                    systemImage: "camera.viewfinder",
                    description: Text("Upgrade to scan cards with the camera.")
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Unlock") { showPaywall = true }
                    }
                }
            } else {
                List {
                    Section {
                        Button("Choose photo / camera") {
                            showPicker = true
                        }
                        if let errorText {
                            Text(errorText).foregroundStyle(.red).font(.caption)
                        }
                    }
                    if !recognized.isEmpty {
                        Section("Recognized text") {
                            ForEach(recognized, id: \.self) { line in
                                Text(line).font(.caption)
                            }
                        }
                    }
                    Section("Matches") {
                        if matches.isEmpty {
                            Text("No matches yet — take a clear photo of the card name and number.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(matches) { card in
                                Button {
                                    add(card)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(card.cardName)
                                        Text("\(card.setCode) · \(card.cardNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Scanner")
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $pickedImage, sourceType: useCamera)
        }
        .onChange(of: pickedImage) { _, new in
            guard let new else { return }
            Task { await runVision(on: new) }
        }
    }

    private func runVision(on image: UIImage) async {
        errorText = nil
        do {
            let strings = try TextRecognition.strings(from: image)
            recognized = strings
            let query = strings.joined(separator: " ")
            matches = await services.cardData.search(query: query)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func add(_ card: Card) {
        let count = (try? modelContext.fetch(FetchDescriptor<CollectionCard>()))?.count ?? 0
        guard FreemiumGate.canAddCollectionRow(currentRowCount: count, isPremium: services.store.isPremium) else {
            return
        }
        let row = CollectionCard(
            masterCardId: card.masterCardId,
            setCode: card.setCode,
            quantity: 1,
            printing: "Standard",
            language: "English",
            conditionId: CardCondition.nearMint.rawValue
        )
        modelContext.insert(row)
    }
}
