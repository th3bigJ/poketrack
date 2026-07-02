import SwiftUI
import SwiftData

struct CreateBinderSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bindrAccent) private var bindrAccent
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @State private var layout = BinderPageLayout.fixed(rows: 3, columns: 3)
    @State private var colourName = "navy"
    @State private var texture = BinderTexture.leather
    @State private var showCardPreview = true
    @State private var showValueOnCover = true
    @State private var showPriceOverlay = false
    @State private var titleTextColor = BinderTitleTextColor.gold.rawValue
    @State private var titleFontStyle = BinderTitleFontStyle.serif
    @State private var embossedCardID: String?
    @State private var embossedPokemonImageUrl: String?
    @State private var embossMode = BinderEmbossMode.fullCard
    @State private var showSaveError = false

    private var transientBinder: Binder {
        let binder = Binder(
            title: name.isEmpty ? "New Binder" : name,
            brand: services.brandSettings.selectedCatalogBrand,
            pageLayout: layout,
            colour: colourName,
            texture: texture,
            showCardPreview: showCardPreview,
            showValueOnCover: showValueOnCover,
            showPriceOverlay: showPriceOverlay,
            titleTextColor: BinderTitleTextColor(rawValue: titleTextColor) ?? .gold,
            titleFontStyle: titleFontStyle
        )
        if BinderTitleTextColor(rawValue: titleTextColor) == nil {
            binder.titleTextColor = titleTextColor
        }
        binder.embossedCardID = embossedCardID
        binder.embossedPokemonImageUrl = embossedPokemonImageUrl
        binder.embossMode = embossMode.rawValue
        return binder
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GeometryReader { proxy in
                        BinderCoverView(
                            binder: transientBinder,
                            compact: false,
                            valueText: showValueOnCover ? "$0.00" : nil
                        )
                        .subtitleOverride("\(services.brandSettings.selectedCatalogBrand.displayTitle) · 0 cards · \(layout.displayName)")
                        .frame(width: proxy.size.width * 0.6)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 320)
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        stylePanel(title: "Details", icon: "character.textbox") {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Name")
                                        .font(.subheadline.weight(.semibold))
                                    TextField("e.g. Charizard Vault", text: $name)
                                        .textFieldStyle(PremiumTextFieldStyle())
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Game")
                                        .font(.subheadline.weight(.semibold))
                                    HStack {
                                        Text(services.brandSettings.selectedCatalogBrand.displayTitle)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }

                        BinderStyleEditorSections(
                            pageLayout: $layout,
                            colour: $colourName,
                            texture: $texture,
                            showPriceOverlay: $showPriceOverlay,
                            showCardPreview: $showCardPreview,
                            showValueOnCover: $showValueOnCover,
                            titleTextColor: $titleTextColor,
                            titleFontStyle: $titleFontStyle,
                            embossedCardID: $embossedCardID,
                            embossedPokemonImageUrl: $embossedPokemonImageUrl,
                            embossMode: $embossMode,
                            catalogBrand: services.brandSettings.selectedCatalogBrand
                        )
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("New Binder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .bold()
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Couldn't save binder", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your binder wasn't saved. Make sure your device has free storage, then tap Create to try again.")
            }
        }
        .presentationDetents([.large])
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let binder = Binder(
            title: trimmedName,
            brand: services.brandSettings.selectedCatalogBrand,
            pageLayout: layout,
            colour: colourName,
            texture: texture,
            showCardPreview: showCardPreview,
            showValueOnCover: showValueOnCover,
            showPriceOverlay: showPriceOverlay,
            titleTextColor: BinderTitleTextColor(rawValue: titleTextColor) ?? .gold,
            titleFontStyle: titleFontStyle
        )
        if BinderTitleTextColor(rawValue: titleTextColor) == nil {
            binder.titleTextColor = titleTextColor
        }
        binder.embossedCardID = embossedCardID
        binder.embossedPokemonImageUrl = embossedPokemonImageUrl
        binder.embossMode = embossMode.rawValue

        modelContext.insert(binder)
        guard modelContext.saveLogging() else {
            modelContext.rollback()
            showSaveError = true
            return
        }
        services.scheduleLibraryCloudBackup()
        dismiss()
    }

    private func stylePanel<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(bindrAccent)
            }
            .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct PremiumTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}
