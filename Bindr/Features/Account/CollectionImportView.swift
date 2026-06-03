import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CollectionImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @State private var selectedSource: CollectionImportSource = .dex
    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var parseResult: DexCollectionCSVImporter.ParseResult?
    @State private var importPlan: CollectionImportPlan?
    @State private var previewError: String?
    @State private var isValidatingCatalog = false
    @State private var validationTask: Task<Void, Never>?

    @State private var isImporting = false
    @State private var importError: String?
    @State private var outcome: CollectionCSVImportOutcome?
    @State private var showPaywall = false

    var body: some View {
        List {
            Section {
                Picker("Import from", selection: $selectedSource) {
                    ForEach(CollectionImportSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
            } footer: {
                Text(selectedSource.subtitle)
            }

            Section {
                Button {
                    resetPreviewState()
                    showFileImporter = true
                } label: {
                    HStack {
                        Label("Choose CSV File", systemImage: "doc.badge.plus")
                        Spacer()
                        if let selectedFileName {
                            Text(selectedFileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(isImporting || isValidatingCatalog)

                if isValidatingCatalog {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking catalog…")
                            .foregroundStyle(.secondary)
                    }
                } else if let importPlan {
                    LabeledContent("Ready to import") {
                        Text("\(importPlan.importableRowCount) rows · \(importPlan.importableCopyCount) cards")
                    }
                    if importPlan.skippedZeroQuantity > 0 {
                        LabeledContent("Skipped (0 qty)") {
                            Text("\(importPlan.skippedZeroQuantity)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let previewError {
                    Text(previewError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("File")
            } footer: {
                Text("Uses Id for the card, Variant for the printing, and Quantity for how many to add. Rows with quantity 0 are ignored.")
            }

            if let importPlan, !importPlan.skipped.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(importPlan.skipped) { row in
                            skippedRowView(row)
                        }
                    } label: {
                        Label(
                            "Won't import (\(importPlan.skipped.count))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Not in catalog")
                } footer: {
                    Text("These card IDs aren't in your downloaded catalogs. Add the game or set under Settings → Card Catalogs, then try again.")
                }
            }

            if let outcome {
                Section("Result") {
                    LabeledContent("Stacks added") {
                        Text("\(outcome.importedCardCount)")
                    }
                    LabeledContent("Cards imported") {
                        Text("\(outcome.importedCopyCount)")
                    }
                    if outcome.stoppedByFreeTierLimit {
                        Text("Import stopped — free tier collection limit reached. Upgrade to Premium to import the rest.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let importError {
                Section {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Import Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { runImport() }
                    .disabled(
                        importPlan == nil
                            || (importPlan?.importable.isEmpty ?? true)
                            || isImporting
                            || isValidatingCatalog
                    )
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: csvContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Importing…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
        .onDisappear {
            validationTask?.cancel()
        }
    }

    @ViewBuilder
    private func skippedRowView(_ row: CollectionImportSkippedRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.cardName ?? row.cardID)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                Text(row.variantDisplayName)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("×\(row.quantity)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(row.cardID)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(row.reason)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 2)
    }

    private func resetPreviewState() {
        validationTask?.cancel()
        parseResult = nil
        importPlan = nil
        previewError = nil
        outcome = nil
        importError = nil
        isValidatingCatalog = false
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            previewError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            loadPreview(from: url)
        }
    }

    private var csvContentTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let csv = UTType(filenameExtension: "csv") { types.append(csv) }
        return types
    }

    private func loadPreview(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        importPlan = nil
        outcome = nil
        importError = nil

        do {
            let parsed = try DexCollectionCSVImporter.parse(fileURL: url)
            parseResult = parsed
            previewError = nil
            validateCatalog(for: parsed)
        } catch {
            parseResult = nil
            previewError = error.localizedDescription
        }
    }

    private func validateCatalog(for parsed: DexCollectionCSVImporter.ParseResult) {
        validationTask?.cancel()
        isValidatingCatalog = true
        validationTask = Task {
            let plan = await CollectionCSVImportService.buildImportPlan(
                parseResult: parsed,
                services: services
            )
            guard !Task.isCancelled else { return }
            importPlan = plan
            isValidatingCatalog = false
        }
    }

    private func runImport() {
        guard let importPlan else { return }

        isImporting = true
        importError = nil
        outcome = nil

        Task {
            let result = await CollectionCSVImportService.importPlan(
                importPlan,
                services: services,
                modelContext: modelContext
            )
            isImporting = false
            switch result {
            case .success(let value):
                outcome = value
                if value.stoppedByFreeTierLimit {
                    showPaywall = true
                }
                Haptics.success()
            case .failure(let error):
                importError = error.localizedDescription
                Haptics.error()
            }
        }
    }
}
