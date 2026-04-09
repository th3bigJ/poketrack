import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var ledgerLines: [LedgerLine]
    
    @State private var selectedDataType: DataType = .wishlist
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    
    enum DataType: String, CaseIterable {
        case wishlist = "Wishlist"
        case collection = "Collection"
        case ledger = "Transaction History"
        case all = "All Data"
        
        var icon: String {
            switch self {
            case .wishlist: return "heart.text.square"
            case .collection: return "square.stack.3d.up"
            case .ledger: return "list.bullet.rectangle"
            case .all: return "doc.text"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DataType.allCases, id: \.self) { type in
                        Button {
                            selectedDataType = type
                        } label: {
                            HStack {
                                Label(type.rawValue, systemImage: type.icon)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedDataType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Data to Export")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        dataCount
                            .font(.headline)
                        dataPreview
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Export CSV") {
                        exportToCSV()
                    }
                    .disabled(dataIsEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    @ViewBuilder
    private var dataCount: some View {
        switch selectedDataType {
        case .wishlist:
            Text("\(wishlistItems.count) wishlist items")
        case .collection:
            Text("\(collectionItems.count) collection items")
        case .ledger:
            Text("\(ledgerLines.count) transaction lines")
        case .all:
            Text("\(wishlistItems.count) wishlist + \(collectionItems.count) collection + \(ledgerLines.count) transactions")
        }
    }
    
    @ViewBuilder
    private var dataPreview: some View {
        switch selectedDataType {
        case .wishlist:
            if let first = wishlistItems.first {
                Text("Sample: Card \(first.cardID), variant: \(first.variantKey)")
            } else {
                Text("No wishlist items")
            }
        case .collection:
            if let first = collectionItems.first {
                Text("Sample: Card \(first.cardID), qty: \(first.quantity)")
            } else {
                Text("No collection items")
            }
        case .ledger:
            if let first = ledgerLines.first {
                Text("Sample: \(first.direction) - \(first.lineDescription)")
            } else {
                Text("No transaction history")
            }
        case .all:
            Text("Exports all three tables as separate CSV files")
        }
    }
    
    private var dataIsEmpty: Bool {
        switch selectedDataType {
        case .wishlist:
            return wishlistItems.isEmpty
        case .collection:
            return collectionItems.isEmpty
        case .ledger:
            return ledgerLines.isEmpty
        case .all:
            return wishlistItems.isEmpty && collectionItems.isEmpty && ledgerLines.isEmpty
        }
    }
    
    private func exportToCSV() {
        let fileName: String
        let csvContent: String
        
        switch selectedDataType {
        case .wishlist:
            fileName = "wishlist-\(dateString()).csv"
            csvContent = generateWishlistCSV()
        case .collection:
            fileName = "collection-\(dateString()).csv"
            csvContent = generateCollectionCSV()
        case .ledger:
            fileName = "ledger-\(dateString()).csv"
            csvContent = generateLedgerCSV()
        case .all:
            // For "all", we'll create a zip or just pick one for now
            fileName = "all-data-\(dateString()).csv"
            csvContent = generateAllDataCSV()
        }
        
        // Save to temporary directory
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            exportURL = tempURL
            showShareSheet = true
        } catch {
            print("Failed to write CSV: \(error)")
        }
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
    
    private func generateWishlistCSV() -> String {
        var rows = ["Card ID,Variant,Date Added,Notes,Collection Name"]
        
        for item in wishlistItems {
            let row = [
                item.cardID,
                item.variantKey,
                ISO8601DateFormatter().string(from: item.dateAdded),
                escapeCSV(item.notes),
                escapeCSV(item.collectionName ?? "")
            ].joined(separator: ",")
            rows.append(row)
        }
        
        return rows.joined(separator: "\n")
    }
    
    private func generateCollectionCSV() -> String {
        var rows = ["Card ID,Variant,Date Acquired,Quantity,Purchase Price,Item Kind,Notes,Grading Company,Grade,Cert #,Sealed Product ID,Sealed Status"]
        
        for item in collectionItems {
            let row = [
                item.cardID,
                item.variantKey,
                ISO8601DateFormatter().string(from: item.dateAcquired),
                String(item.quantity),
                item.purchasePrice.map { String($0) } ?? "",
                item.itemKind,
                escapeCSV(item.notes),
                escapeCSV(item.gradingCompany ?? ""),
                escapeCSV(item.grade ?? ""),
                escapeCSV(item.certNumber ?? ""),
                escapeCSV(item.sealedProductId ?? ""),
                escapeCSV(item.sealedStatus ?? "")
            ].joined(separator: ",")
            rows.append(row)
        }
        
        return rows.joined(separator: "\n")
    }
    
    private func generateLedgerCSV() -> String {
        var rows = ["ID,Date,Direction,Product Kind,Description,Card ID,Variant,Quantity,Unit Price,Currency,Fees,Counterparty,Channel,External Ref"]
        
        for line in ledgerLines {
            let row = [
                line.id.uuidString,
                ISO8601DateFormatter().string(from: line.occurredAt),
                line.direction,
                line.productKind,
                escapeCSV(line.lineDescription),
                escapeCSV(line.cardID ?? ""),
                escapeCSV(line.variantKey ?? ""),
                String(line.quantity),
                line.unitPrice.map { String($0) } ?? "",
                line.currencyCode,
                line.feesAmount.map { String($0) } ?? "",
                escapeCSV(line.counterparty ?? ""),
                escapeCSV(line.channel ?? ""),
                escapeCSV(line.externalRef ?? "")
            ].joined(separator: ",")
            rows.append(row)
        }
        
        return rows.joined(separator: "\n")
    }
    
    private func generateAllDataCSV() -> String {
        // Combine all three exports into one mega CSV with sections
        var output = "=== WISHLIST ===\n"
        output += generateWishlistCSV()
        output += "\n\n=== COLLECTION ===\n"
        output += generateCollectionCSV()
        output += "\n\n=== LEDGER ===\n"
        output += generateLedgerCSV()
        return output
    }
    
    private func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

#Preview {
    DataExportView()
        .modelContainer(for: [WishlistItem.self, CollectionItem.self, LedgerLine.self])
}
