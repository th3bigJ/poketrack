import SwiftUI
import SwiftData

struct CreateBinderSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
    @State private var titleTextColor = BinderTitleTextColor.gold
    @State private var titleFontStyle = BinderTitleFontStyle.serif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Premium Preview
                    BinderCoverView(
                        title: name,
                        subtitle: "\(services.brandSettings.selectedCatalogBrand.displayTitle) · 0 cards · \(layout.displayName)",
                        colourName: colourName,
                        texture: texture,
                        seed: 1, // Fixed seed for creation preview
                        peekingCardURLs: [nil, nil, nil],
                        showCardPreview: showCardPreview,
                        titleTextColor: titleTextColor,
                        titleFontStyle: titleFontStyle
                    )
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

                        // 3. Layout Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LAYOUT")
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
                                    .background(layout == .freeScroll ? Color.accentColor.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay {
                                        if layout == .freeScroll {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.accentColor, lineWidth: 1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .gridCellColumns(3)
                            }
                        }

                        // 4. Style Section (Colors + Texture Info)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("STYLE")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 20) {
                                // Color Grid
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                    ForEach(BinderColourPalette.pickerOptions, id: \.name) { swatch in
                                        Circle()
                                            .fill(swatch.color)
                                            .frame(width: 32, height: 32)
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
                                
                                // Texture Segment/Picker
                                Picker("Texture", selection: $texture) {
                                    ForEach(BinderTexture.allCases) { tex in
                                        Text(tex.displayName).tag(tex)
                                    }
                                }
                                .pickerStyle(.segmented)

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
                                
                                // Selected Style Label
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(BinderColourPalette.color(named: colourName))
                                        .frame(width: 8, height: 8)
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

                        // 5. Cover Options — toggle the fanned card preview on
                        //    the front of the binder. Some users prefer the
                        //    clean material look; keep both options available.
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COVER")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
            titleTextColor: titleTextColor,
            titleFontStyle: titleFontStyle
        )
        modelContext.insert(binder)
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
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: 1)
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
