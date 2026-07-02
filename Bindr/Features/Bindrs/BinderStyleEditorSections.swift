import SwiftUI
import UIKit

/// Shared page layout, material, and front-cover controls used by both
/// ``CreateBinderSheet`` and ``BinderStylePickerSheet``.
struct BinderStyleEditorSections: View {
    enum CoverDisplayMode: String, CaseIterable, Identifiable {
        case clean
        case cards
        case embossed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cards: return "Cards"
            case .clean: return "Clean"
            case .embossed: return "Embossed"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent

    @Binding var pageLayout: BinderPageLayout
    @Binding var colour: String
    @Binding var texture: BinderTexture
    @Binding var showPriceOverlay: Bool
    @Binding var showCardPreview: Bool
    @Binding var showValueOnCover: Bool
    @Binding var titleTextColor: String
    @Binding var titleFontStyle: BinderTitleFontStyle
    @Binding var embossedCardID: String?
    @Binding var embossedPokemonImageUrl: String?
    @Binding var embossMode: BinderEmbossMode

    /// Card IDs used to seed the embossed-card picker when the search field is empty.
    var embossedCandidateCardIDs: [String] = []
    var catalogBrand: TCGBrand

    @State private var coverDisplayMode: CoverDisplayMode = .cards
    @State private var pokemonQuery = ""
    @State private var embossedCardQuery = ""
    @State private var embossedCardCandidates: [Card] = []
    @State private var isSearchingEmbossedCards = false

    private let layoutOptions: [BinderPageLayout] = [
        .fixed(rows: 2, columns: 2),
        .fixed(rows: 3, columns: 2),
        .fixed(rows: 3, columns: 3),
        .fixed(rows: 4, columns: 3),
        .fixed(rows: 3, columns: 4),
        .fixed(rows: 4, columns: 4)
    ]

    private var hasEmbossSelection: Bool {
        embossedCardID != nil || embossedPokemonImageUrl != nil
    }

    private var coverTextColorBinding: Binding<Color> {
        Binding(
            get: {
                if let custom = customTitleTextColor {
                    return custom
                }
                let kind = BinderTitleTextColor(rawValue: titleTextColor) ?? .gold
                return kind == .gold
                    ? BinderColourPalette.color(named: colour)
                    : kind.swiftUIColor
            },
            set: { titleTextColor = hexString(from: $0, fallback: titleTextColor) }
        )
    }

    private var customTitleTextColor: Color? {
        guard BinderTitleTextColor(rawValue: titleTextColor) == nil else { return nil }
        let normalized = titleTextColor.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6 || normalized.count == 8 else { return nil }
        return Color(hex: normalized)
    }

    private var binderColourBinding: Binding<Color> {
        Binding(
            get: { BinderColourPalette.color(named: colour) },
            set: { colour = hexString(from: $0, fallback: colour) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stylePanel(title: "Page layout", icon: "square.grid.3x3") {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(layoutOptions, id: \.self) { option in
                            layoutButton(for: option)
                        }

                        Button {
                            pageLayout = .freeScroll
                        } label: {
                            HStack {
                                Image(systemName: "square.grid.3x3")
                                Text("Free flow")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(pageLayout.isFreeScroll ? bindrAccent.opacity(0.1) : Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                if pageLayout.isFreeScroll {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(bindrAccent, lineWidth: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .gridCellColumns(3)
                    }

                    Toggle(isOn: $showPriceOverlay) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show card prices")
                                    .font(.subheadline.weight(.semibold))
                                Text("Adds subtle market-price badges to binder page cards")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "tag")
                                .foregroundStyle(bindrAccent)
                        }
                    }
                    .tint(bindrAccent)
                }
            }

            stylePanel(title: "Binder style", icon: "swatchpalette") {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(BinderColourPalette.pickerOptions, id: \.name) { swatch in
                            colorSwatchButton(swatch)
                        }
                        customColourPickerButton
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(BinderTexture.allCases) { option in
                            textureButton(option)
                        }
                    }
                }
            }

            stylePanel(title: "Front cover", icon: "rectangle.portrait") {
                VStack(spacing: 12) {
                    ForEach(CoverDisplayMode.allCases) { mode in
                        coverModeRow(mode)
                    }

                    Divider()

                    Toggle(isOn: $showValueOnCover) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show value")
                                    .font(.subheadline.weight(.semibold))
                                Text("Adds the collection value to the cover")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sterlingsign.circle")
                                .foregroundStyle(bindrAccent)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Color(uiColor: .systemGreen))

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cover text")
                            .font(.subheadline.weight(.semibold))

                        ColorPicker(
                            "Text colour",
                            selection: coverTextColorBinding,
                            supportsOpacity: false
                        )
                        .font(.subheadline.weight(.semibold))

                        Button("Match binder tint") {
                            titleTextColor = BinderTitleTextColor.gold.rawValue
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bindrAccent)
                        .buttonStyle(.plain)

                        Picker("Title font", selection: $titleFontStyle) {
                            ForEach(BinderTitleFontStyle.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(colorScheme == .dark ? .white : .black)
                    }
                }
            }

            if coverDisplayMode == .embossed {
                stylePanel(title: "Embossed art", icon: "sparkles") {
                    embossedArtSection
                }
            }
        }
        .onAppear {
            syncCoverDisplayModeFromState()
        }
        .onChange(of: coverDisplayMode) { _, mode in
            applyCoverDisplayMode(mode)
        }
        .onChange(of: showCardPreview) { _, _ in
            syncCoverDisplayModeFromState()
        }
        .onChange(of: embossedCardID) { _, _ in
            syncCoverDisplayModeFromState()
        }
        .onChange(of: embossedPokemonImageUrl) { _, _ in
            syncCoverDisplayModeFromState()
        }
        .task(id: embossedCardQuery) {
            await refreshEmbossedCardCandidates()
        }
    }

    // MARK: - Embossed art

    @ViewBuilder
    private var embossedArtSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Emboss Mode", selection: $embossMode) {
                ForEach(BinderEmbossMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(colorScheme == .dark ? .white : .black)

            if embossMode == .character {
                characterEmbossPicker
            } else {
                fullCardEmbossPicker
            }
        }
    }

    private var characterEmbossPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Character")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Pokémon", text: $pokemonQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .inlineSearchFieldChrome(cornerRadius: 12)

            let allPokemon = services.cardData.nationalDexPokemonSorted()
            let filteredPokemon: [NationalDexPokemon] = {
                let q = pokemonQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !q.isEmpty else { return allPokemon }
                return allPokemon.filter {
                    $0.name.lowercased().contains(q) ||
                    $0.displayName.lowercased().contains(q) ||
                    String($0.nationalDexNumber).contains(q)
                }
            }()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                if pokemonQuery.isEmpty {
                    noneEmbossButton(
                        isSelected: embossedPokemonImageUrl == nil && embossedCardID == nil
                    ) {
                        embossedPokemonImageUrl = nil
                        embossedCardID = nil
                    }
                }

                ForEach(filteredPokemon) { mon in
                    Button {
                        embossedPokemonImageUrl = mon.imageUrl
                        embossedCardID = nil
                    } label: {
                        VStack(spacing: 5) {
                            CachedAsyncImage(url: AppConfiguration.pokemonArtURL(imageFileName: mon.imageUrl)) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Color.secondary.opacity(0.1)
                            }
                            .frame(height: 58)
                            Text(mon.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(
                            embossedPokemonImageUrl == mon.imageUrl
                                ? bindrAccent.opacity(0.14)
                                : Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            if embossedPokemonImageUrl == mon.imageUrl {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(bindrAccent, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .task {
                if services.cardData.nationalDexPokemon.isEmpty {
                    await services.cardData.loadNationalDexPokemon()
                }
            }
        }
    }

    private var fullCardEmbossPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Full card")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search all eligible cards", text: $embossedCardQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if isSearchingEmbossedCards {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .inlineSearchFieldChrome(cornerRadius: 12)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                noneEmbossButton(
                    isSelected: embossedCardID == nil && embossedPokemonImageUrl == nil
                ) {
                    embossedCardID = nil
                    embossedPokemonImageUrl = nil
                }

                ForEach(embossedCardCandidates) { card in
                    Button {
                        embossedCardID = card.masterCardId
                        embossedPokemonImageUrl = nil
                    } label: {
                        VStack(spacing: 5) {
                            let url = AppConfiguration.imageURL(relativePath: card.displayImageSrc)
                            CachedAsyncImage(url: url, targetSize: CGSize(width: 132, height: 184)) { img in
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.secondary.opacity(0.1)
                            }
                            .frame(width: 58, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                            Text(card.cardName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(
                            embossedCardID == card.masterCardId
                                ? bindrAccent.opacity(0.14)
                                : Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            if embossedCardID == card.masterCardId {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(bindrAccent, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func noneEmbossButton(isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: "slash.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: 58)
                Text("None")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? bindrAccent.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(bindrAccent, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cover mode

    private func syncCoverDisplayModeFromState() {
        if showCardPreview {
            coverDisplayMode = .cards
        } else if hasEmbossSelection || coverDisplayMode == .embossed {
            coverDisplayMode = .embossed
        } else {
            coverDisplayMode = .clean
        }
    }

    private func applyCoverDisplayMode(_ mode: CoverDisplayMode) {
        switch mode {
        case .cards:
            showCardPreview = true
        case .clean:
            showCardPreview = false
            embossedCardID = nil
            embossedPokemonImageUrl = nil
        case .embossed:
            showCardPreview = false
        }
    }

    private func coverModeRow(_ mode: CoverDisplayMode) -> some View {
        let isSelected = coverDisplayMode == mode
        return Button {
            coverDisplayMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: coverModeIcon(mode))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? bindrAccent : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        (isSelected ? bindrAccent.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                    Text(coverModeSubtitle(mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(bindrAccent)
                }
            }
            .foregroundStyle(.primary)
            .padding(12)
            .background(
                isSelected ? bindrAccent.opacity(0.08) : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? bindrAccent.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func coverModeIcon(_ mode: CoverDisplayMode) -> String {
        switch mode {
        case .cards: return "rectangle.stack.fill"
        case .clean: return "rectangle.portrait.fill"
        case .embossed: return "sparkles"
        }
    }

    private func coverModeSubtitle(_ mode: CoverDisplayMode) -> String {
        switch mode {
        case .cards: return "Fan the first cards across the cover"
        case .clean: return "Keep the material and title uncluttered"
        case .embossed: return "Press a card or character into the surface"
        }
    }

    // MARK: - Colour + texture

    private var isCustomBinderColour: Bool {
        let normalized = colour.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return normalized.count == 6 || normalized.count == 8
    }

    private func colorSwatchButton(_ swatch: (name: String, color: Color)) -> some View {
        let isSelected = colour == swatch.name
        return Button {
            colour = swatch.name
        } label: {
            binderColourSwatch(name: swatch.name, color: swatch.color, size: 36)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.primary.opacity(0.35) : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BinderColourPalette.displayName(for: swatch.name))
    }

    private var customColourPickerButton: some View {
        let isSelected = isCustomBinderColour
        let displayColor = BinderColourPalette.color(named: colour)

        return ColorPicker(
            selection: binderColourBinding,
            supportsOpacity: false
        ) {
            Group {
                if isSelected {
                    binderColourSwatch(name: colour, color: displayColor, size: 36)
                } else {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .red],
                                        center: .center
                                    ),
                                    lineWidth: 2.5
                                )
                        }
                        .overlay {
                            Image(systemName: "eyedropper.halffull")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.primary.opacity(0.35) : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                }
            }
            .frame(width: 36, height: 36)
        }
        .labelsHidden()
        .accessibilityLabel("Custom binder colour")
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

    private func textureButton(_ option: BinderTexture) -> some View {
        let isSelected = texture == option
        return Button {
            texture = option
        } label: {
            HStack(spacing: 8) {
                Image(systemName: option.pickerSymbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(option.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? bindrAccent : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                isSelected ? bindrAccent.opacity(0.10) : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? bindrAccent.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layout

    @ViewBuilder
    private func layoutButton(for option: BinderPageLayout) -> some View {
        let isSelected = pageLayout == option
        Button {
            pageLayout = option
        } label: {
            VStack(spacing: 4) {
                gridIcon(for: option)
                    .font(.system(size: 16))
                Text("\(option.columns) × \(option.rows)")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? bindrAccent.opacity(0.1) : Color(uiColor: .tertiarySystemGroupedBackground))
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

    // MARK: - Search helpers

    private func refreshEmbossedCardCandidates() async {
        let query = embossedCardQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchingEmbossedCards = !query.isEmpty
        defer { isSearchingEmbossedCards = false }

        let cards: [Card]
        if query.isEmpty {
            var resolved: [Card] = []
            var seen = Set<String>()
            for cardID in embossedCandidateCardIDs {
                guard seen.insert(cardID).inserted,
                      let card = await services.cardData.loadCard(masterCardId: cardID)
                else { continue }
                resolved.append(card)
            }
            cards = resolved
        } else {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            cards = await services.cardData.searchByName(
                query: query,
                catalogBrand: catalogBrand
            )
        }

        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        embossedCardCandidates = cards
            .filter {
                !$0.displayImageSrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && seen.insert($0.masterCardId).inserted
            }
            .prefix(60)
            .map { $0 }
    }

    private func hexString(from color: Color, fallback: String) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return fallback
        }
        return String(
            format: "%02x%02x%02x",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}
