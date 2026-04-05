import SwiftData
import SwiftUI

struct TransactionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var rows: [LedgerTransaction]

    @State private var showPaywall = false
    @State private var showAdd = false

    var body: some View {
        Group {
            if !services.store.isPremium {
                ContentUnavailableView(
                    "Premium only",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Upgrade to log purchases and trades.")
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Unlock") { showPaywall = true }
                    }
                }
            } else {
                List {
                    ForEach(rows, id: \.id) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.transactionDescription).font(.headline)
                            Text(t.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let total = t.totalPrice {
                                Text(String(format: "£%.2f", total))
                                    .font(.subheadline)
                            }
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAdd = true
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showAdd) {
                    AddTransactionSheet()
                }
            }
        }
        .navigationTitle("Transactions")
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(rows[i])
        }
    }
}

struct AddTransactionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var desc = ""
    @State private var amount = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $desc)
                TextField("Total GBP", text: $amount)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("New transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let total = Double(amount.replacingOccurrences(of: ",", with: "."))
                        let t = LedgerTransaction(direction: "purchase", transactionDescription: desc, quantity: 1, date: date)
                        t.totalPrice = total
                        modelContext.insert(t)
                        dismiss()
                    }
                    .disabled(desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
