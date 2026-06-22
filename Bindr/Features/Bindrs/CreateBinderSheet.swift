import SwiftUI
import SwiftData

struct CreateBinderSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bindrAccent) private var bindrAccent

    private let layoutOptions: [BinderPageLayout] = [
        .fixed(rows: 2, columns: 2),
        .fixed(rows: 3, columns: 2),
        .fixed(rows: 3, columns: 3),
        .fixed(rows: 4, columns: 3),
        .fixed(rows: 3, columns: 4),
        .fixed(rows: 4, columns: 4)
    ]

    @State private var name = ""
    @State private var layout = BinderPageLayout.fixed(rows: 3, columns: 3)
    @State private var colourName = "navy"
    @State private var texture = BinderTexture.leather
    @State private var showCardPreview = true
    @State private var showValueOnCover = true
    @State private var showPriceOverlay = false
    @State private var titleTextColor = BinderTitleTextColor.gold
    @State private var titleFontStyle = BinderTitleFontStyle.serif
    @State private var showSaveError = false

    private var transientBinder: Binder {
        Binder(
            title: name.isEmpty ? "New Binder" : name,
            brand: services.brandSettings.selectedCatalogBrand,
            pageLayout: layout,
            colour: colourName,
            texture: texture,
            showCardPreview: showCardPreview,
            showValueOnCover: showValueOnCover,
            showPriceOverlay: showPriceOverlay,
            titleTextColor: titleTextColor,
            titleFontStyle: titleFontStyle
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Premium Preview
                    GeometryReader { proxy in
                        BinderCoverView(
                            binder: transientBinder,
                            compact: false,
                            valueText: showValueOnCover ? "$0.00" : nil
                        )
                        .subtitleOverride("\(services.brandSettings.selectedCatalogBrand.displayTitle) · 0 cards · \(layout.displayName)")
                        .frame(width: min(proxy.size.width * 0.62, 260))
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 320)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 20) {
                        // 2. Name Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            
                            TextField("e.g. Charizard Vault", text: $name)
                                .textFieldStyle(PremiumTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("GAME")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            HStack {
                                Text(services.brandSettings.selectedCatalogBrand.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // 3. Page layout + card prices
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PAGE LAYOUT")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(layoutOptions, id: \.self) { option in
                                    layoutButton(for: option)
                                }
                                
                                Button {
                                    layout = .freeScroll
                                } label: {
                                    HStack {
                                        Image(systemName: "square.grid.3x3")
                                        Text("Free flow")
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(layout == .freeScroll ? bindrAccent.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay {
                                        if layout == .freeScroll {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(bindrAccent, lineWidth: 1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .gridCellColumns(3)
                            }

                            Toggle(isOn: $showPriceOverlay) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show card prices")
                                        .font(.subheadline.weight(.medium))
                                    Text("Add subtle market-price badges on binder pages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.accentColor)
                        }

                        // 4. Binder style (colour + texture)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("BINDER STYLE")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 20) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                    ForEach(BinderColourPalette.pickerOptions, id: \.name) { swatch in
                                        binderColourSwatch(name: swatch.name, color: swatch.color, size: 32)
                                            .overlay {
                                                if colourName == swatch.name {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            .onTapGesture {
                                                colourName = swatch.name
                                            }
                                    }
                                }
                                
                                Picker("Texture", selection: $texture) {
                                    ForEach(BinderTexture.allCases) { tex in
                                        Text(tex.displayName).tag(tex)
                                    }
                                }
                                .pickerStyle(.segmented)

                                HStack(spacing: 4) {
                                    binderColourSwatch(
                                        name: colourName,
                                        color: BinderColourPalette.color(named: colourName),
                                        size: 8
                                    )
                                    Text("Style: ")
                                        .foregroundStyle(.secondary)
                                    Text("\(BinderColourPalette.displayName(for: colourName)) \(texture.displayName)")
                                        .bold()
                                }
                                .font(.caption)
                            }
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // 5. Front cover + cover text
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FRONT COVER")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            VStack(spacing: 14) {
                                Toggle(isOn: $showCardPreview) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Show cards on cover")
                                            .font(.subheadline.weight(.medium))
                                        Text("Preview the first few cards on the binder front")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tint(.accentColor)

                                Toggle(isOn: $showValueOnCover) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Show value on cover")
                                            .font(.subheadline.weight(.medium))
                                        Text("Display the binder value label on the front")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tint(.accentColor)

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Cover text")
                                        .font(.subheadline.weight(.semibold))

                                    Picker("Title text color", selection: $titleTextColor) {
                                        ForEach(BinderTitleTextColor.allCases) { option in
                                            Text(option.displayName).tag(option)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    Picker("Title font", selection: $titleFontStyle) {
                                        ForEach(BinderTitleFontStyle.allCases) { option in
                                            Text(option.displayName).tag(option)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("New Binder")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .bold()
                    .foregroundStyle(.primary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Couldn't save binder", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your binder wasn't saved. Make sure your device has free storage, then tap Create to try again.")
            }
        }
    }

    private func create() {
        let binder = Binder(
            title: name.trimmingCharacters(in: .whitespaces),
            brand: services.brandSettings.selectedCatalogBrand,
            pageLayout: layout,
            colour: colourName,
            texture: texture,
            showCardPreview: showCardPreview,
            showValueOnCover: showValueOnCover,
            showPriceOverlay: showPriceOverlay,
            titleTextColor: titleTextColor,
            titleFontStyle: titleFontStyle
        )
        modelContext.insert(binder)
        // Only treat the binder as created once the on-device save actually succeeds.
        // On failure, discard the pending insert so the form stays intact for a clean retry.
        guard modelContext.saveLogging() else {
            modelContext.rollback()
            showSaveError = true
            return
        }
        services.scheduleLibraryCloudBackup()
        dismiss()
    }

    @ViewBuilder
    private func layoutButton(for option: BinderPageLayout) -> some View {
        let isSelected = layout == option
        Button {
            layout = option
        } label: {
            VStack(spacing: 4) {
                gridIcon(for: option)
                    .font(.system(size: 16))
                Text("\(option.columns) × \(option.rows)")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? bindrAccent.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? bindrAccent : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(bindrAccent, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func gridIcon(for option: BinderPageLayout) -> Image {
        switch (option.columns, option.rows) {
        case (2, 2): return Image(systemName: "square.grid.2x2.fill")
        default: return Image(systemName: "square.grid.3x3.fill")
        }
    }

    private func binderColourSwatch(name: String, color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .overlay {
                if name == BinderColourPalette.logoColourName {
                    Circle()
                        .fill(BinderColourPalette.logoGradient)
                }
            }
            .frame(width: size, height: size)
    }
}

private struct PremiumTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
    }
}
