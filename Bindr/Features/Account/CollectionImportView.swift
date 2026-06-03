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
    @State private var preview: DexCollectionCSVImporter.ParseResult?
    @State private var previewError: String?

    @State private var isImporting = false
    @State private var importError: String?
    @State private var outcome: CollectionCSVImportOutcome?
    @State private var showPaywall = false

    private var importableRowCount: Int {
        preview?.rows.count ?? 0
    }

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
                    preview = nil
                    previewError = nil
                    outcome = nil
                    importError = nil
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
                .disabled(isImporting)

                if let preview {
                    LabeledContent("Rows to import") {
                        Text("\(preview.rows.count)")
                    }
                    if preview.skippedZeroQuantity > 0 {
                        LabeledContent("Skipped (0 qty)") {
                            Text("\(preview.skippedZeroQuantity)")
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

            if let outcome {
                Section("Result") {
                    LabeledContent("Stacks added") {
                        Text("\(outcome.importedCardCount)")
                    }
                    LabeledContent("Cards imported") {
                        Text("\(outcome.importedCopyCount)")
                    }
                    if outcome.skippedUnknownCards > 0 {
                        LabeledContent("Not in catalog") {
                            Text("\(outcome.skippedUnknownCards)")
                                .foregroundStyle(.orange)
                        }
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
                    .disabled(preview == nil || isImporting)
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
        do {
            preview = try DexCollectionCSVImporter.parse(fileURL: url)
            previewError = nil
        } catch {
            preview = nil
            previewError = error.localizedDescription
        }
    }

    private func runImport() {
        guard let preview else { return }
        guard let url = selectedFileURL else {
            importError = "Choose a CSV file first."
            return
        }

        isImporting = true
        importError = nil
        outcome = nil

        Task {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let result = await CollectionCSVImportService.importFile(
                url: url,
                source: selectedSource,
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
