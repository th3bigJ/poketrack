import SwiftUI

private enum DashboardProgressPickerStep: Equatable {
    case manage
    case chooseKind
    case chooseSet
    case choosePokemon
    case chooseMode(DashboardProgressDraft)
}

private struct DashboardProgressDraft: Equatable {
    var kind: DashboardProgressTargetKind
    var setCode: String?
    var setName: String?
    var dexId: Int?
    var pokemonDisplayName: String?
}

struct DashboardProgressTrackerSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var progressTracker: DashboardProgressTrackerStore
    let snapshots: [DashboardProgressSnapshot]
    let onChange: () -> Void

    @State private var step: DashboardProgressPickerStep = .manage
    @State private var setQuery = ""
    @State private var pokemonQuery = ""
    @State private var selectedMode: SetCompletionMode = .full
    @State private var pokemonRows: [NationalDexPokemon] = []
    @State private var isLoadingPokemon = false

    private var toolbarTint: Color {
        colorScheme == .dark ? .white : .black
    }

    private var canAddMoreTargets: Bool {
        progressTracker.targets.count < DashboardProgressTrackerStore.maxTargets
    }

    private var filteredSets: [TCGSet] {
        let sets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        let trimmed = setQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sets }
        let q = trimmed.lowercased()
        return sets.filter {
            $0.name.lowercased().contains(q) || $0.setCode.lowercased().contains(q)
        }
    }

    private var filteredPokemon: [NationalDexPokemon] {
        let trimmed = pokemonQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pokemonRows }
        let q = trimmed.lowercased()
        return pokemonRows.filter {
            $0.name.lowercased().contains(q)
                || $0.displayName.lowercased().contains(q)
                || String($0.nationalDexNumber).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .manage:
                    manageTargetsStep
                case .chooseKind:
                    chooseKindStep
                case .chooseSet:
                    chooseSetStep
                case .choosePokemon:
                    choosePokemonStep
                case .chooseMode(let draft):
                    chooseModeStep(draft: draft)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassToolbarButton()
                }

                if step == .manage, canAddMoreTargets {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                step = .chooseKind
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("Add tracker")
                    }
                }
            }
        }
        .tint(toolbarTint)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var navigationTitle: String {
        switch step {
        case .manage: return "Continue Collecting"
        case .chooseKind: return "Track Progress"
        case .chooseSet: return "Choose a Set"
        case .choosePokemon: return "Choose Pokémon"
        case .chooseMode: return "Completion Goal"
        }
    }

    private var showsBackButton: Bool {
        switch step {
        case .manage: return false
        default: return true
        }
    }

    private var sheetBackButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                goBack()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Back")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(services.theme.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func goBack() {
        switch step {
        case .manage:
            break
        case .chooseKind:
            step = .manage
        case .chooseSet, .choosePokemon:
            step = .chooseKind
        case .chooseMode(let draft):
            step = draft.kind == .set ? .chooseSet : .choosePokemon
        }
    }

    private var manageTargetsStep: some View {
        Group {
            if progressTracker.targets.isEmpty {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Track completion for TCG sets or every print of a Pokémon across your catalog.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            step = .chooseKind
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(services.theme.accentColor)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Add a set or Pokémon")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Full, master, or grand master completion")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    Section {
                        ForEach(progressTracker.targets) { target in
                            manageTargetRow(target)
                        }
                        .onMove { source, destination in
                            progressTracker.move(from: source, to: destination)
                            onChange()
                        }
                        .onDelete { indices in
                            progressTracker.remove(atOffsets: indices)
                            onChange()
                        }
                    } footer: {
                        Text("Drag to reorder. Swipe left to remove a tracker.")
                            .font(.caption)
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    private func manageTargetRow(_ target: DashboardProgressTarget) -> some View {
        let snapshot = snapshots.first { $0.targetID == target.id }

        return HStack(spacing: 12) {
            manageTargetThumbnail(target: target, snapshot: snapshot)

            VStack(alignment: .leading, spacing: 4) {
                Text(target.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(target.completionMode.chipLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let snapshot {
                    Text("\(snapshot.collected) / \(snapshot.total) · \(Int(snapshot.progress * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(manageTargetAccessibilityLabel(target: target, snapshot: snapshot))
    }

    private func manageTargetAccessibilityLabel(
        target: DashboardProgressTarget,
        snapshot: DashboardProgressSnapshot?
    ) -> String {
        if let snapshot {
            return "\(target.displayTitle), \(target.completionMode.chipLabel), \(snapshot.collected) of \(snapshot.total)"
        }
        return "\(target.displayTitle), \(target.completionMode.chipLabel)"
    }

    @ViewBuilder
    private func manageTargetThumbnail(
        target: DashboardProgressTarget,
        snapshot: DashboardProgressSnapshot?
    ) -> some View {
        if let url = snapshot?.artworkURL {
            CachedAsyncImage(url: url, targetSize: CGSize(width: 72, height: 72)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.primary.opacity(0.06)
            }
            .frame(width: 40, height: 40)
        } else if target.kind == .set,
                  let setCode = target.setCode,
                  let set = services.cardData.allSetsSortedByReleaseDateNewestFirst()
            .first(where: { $0.setCode.lowercased() == setCode.lowercased() }) {
            setLogoThumbnail(for: set)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                Image(systemName: target.kind == .set ? "square.stack.3d.up.fill" : "hare.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
        }
    }

    private var chooseKindStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            if showsBackButton { sheetBackButton }

            Text("Follow completion for a TCG set or every print of a Pokémon across your catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                pickerKindRow(
                    title: "Track a Set",
                    subtitle: "Full, master, or grand master set completion",
                    systemImage: "square.stack.3d.up.fill"
                ) {
                    step = .chooseSet
                }

                Divider().padding(.leading, 46)

                pickerKindRow(
                    title: "Track a Pokémon",
                    subtitle: "Every card featuring that National Dex entry",
                    systemImage: "hare.fill"
                ) {
                    step = .choosePokemon
                    Task { await loadPokemonIfNeeded() }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pickerKindRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(services.theme.accentColor)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chooseSetStep: some View {
        VStack(spacing: 0) {
            if showsBackButton { sheetBackButton.frame(maxWidth: .infinity, alignment: .leading) }
            List {
            Section {
                BrowseInlineSearchField(title: "Search sets", text: $setQuery)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(filteredSets, id: \.setCode) { set in
                    Button {
                        Haptics.lightImpact()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            step = .chooseMode(DashboardProgressDraft(
                                kind: .set,
                                setCode: set.setCode,
                                setName: set.name
                            ))
                        }
                    } label: {
                        HStack(spacing: 12) {
                            setLogoThumbnail(for: set)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(set.setCode.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        }
    }

    private var choosePokemonStep: some View {
        Group {
            if isLoadingPokemon {
                ProgressView("Loading Pokédex…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if services.brandSettings.selectedCatalogBrand != .pokemon {
                ContentUnavailableView(
                    "Pokémon catalog required",
                    systemImage: "hare",
                    description: Text("Switch your active game to Pokémon to track Pokédex completion.")
                )
            } else if pokemonRows.isEmpty {
                ContentUnavailableView(
                    "No Pokédex data",
                    systemImage: "hare",
                    description: Text("Pokédex entries will appear once the catalog finishes loading.")
                )
            } else {
                VStack(spacing: 0) {
                    if showsBackButton { sheetBackButton.frame(maxWidth: .infinity, alignment: .leading) }
                    List {
                    Section {
                        BrowseInlineSearchField(title: "Search Pokémon", text: $pokemonQuery)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(filteredPokemon) { pokemon in
                            Button {
                                Haptics.lightImpact()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    step = .chooseMode(DashboardProgressDraft(
                                        kind: .pokemon,
                                        dexId: pokemon.nationalDexNumber,
                                        pokemonDisplayName: pokemon.displayName
                                    ))
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(
                                        url: AppConfiguration.pokemonArtURL(imageFileName: pokemon.imageUrl),
                                        targetSize: CGSize(width: 72, height: 72)
                                    ) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        Color.primary.opacity(0.06)
                                    }
                                    .frame(width: 36, height: 36)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pokemon.displayName)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("#\(pokemon.nationalDexNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private func chooseModeStep(draft: DashboardProgressDraft) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if showsBackButton { sheetBackButton }
            VStack(alignment: .leading, spacing: 6) {
                Text(draftTitle(draft))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(draft.kind == .set ? "How do you want to measure completion?" : "Track unique cards or every eligible variant?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(SetCompletionMode.allCases, id: \.self) { mode in
                    completionModeChip(mode)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(modeDescription(selectedMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                addTarget(from: draft)
            } label: {
                Text("Start Tracking")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .bindrProminentButtonStyle(size: .flexible)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedMode = .full
        }
    }

    private func draftTitle(_ draft: DashboardProgressDraft) -> String {
        switch draft.kind {
        case .set:
            return draft.setName ?? draft.setCode?.uppercased() ?? "Set"
        case .pokemon:
            return draft.pokemonDisplayName ?? "Pokémon"
        }
    }

    private func completionModeChip(_ mode: SetCompletionMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedMode = mode
            }
            Haptics.lightImpact()
        } label: {
            Text(mode.chipLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .bindrAccentFill(
                            isSelected ? services.theme.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06),
                            usesLogoGradient: isSelected
                        )
                }
                .foregroundStyle(
                    isSelected
                        ? (services.theme.isGradientThemeSelected
                            ? Color.white
                            : services.theme.accentColor.bindrLabelOnFill(in: colorScheme))
                        : .primary.opacity(0.85)
                )
        }
        .buttonStyle(.plain)
    }

    private func modeDescription(_ mode: SetCompletionMode) -> String {
        switch mode {
        case .full:
            return "Count each unique card once — ideal for completing the standard set list."
        case .master:
            return "Count every master-set variant slot, including holos and reverse holos where applicable."
        case .grandMaster:
            return "The widest goal — includes master-set slots plus grand master extras such as stamps and promos."
        }
    }

    @ViewBuilder
    private func setLogoThumbnail(for set: TCGSet) -> some View {
        let logoURL = AppConfiguration.setLogoURLCandidates(
            logoSrc: set.logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
        ).first

        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            if let logoURL {
                CachedAsyncImage(url: logoURL, targetSize: CGSize(width: 64, height: 64)) { image in
                    image.resizable().scaledToFit().padding(4)
                } placeholder: {
                    ProgressView().scaleEffect(0.6)
                }
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
    }

    private func loadPokemonIfNeeded() async {
        guard pokemonRows.isEmpty else { return }
        isLoadingPokemon = true
        defer { isLoadingPokemon = false }
        await services.cardData.loadNationalDexPokemon()
        pokemonRows = services.cardData.nationalDexPokemonSorted()
    }

    private func addTarget(from draft: DashboardProgressDraft) {
        let target = DashboardProgressTarget(
            kind: draft.kind,
            setCode: draft.setCode,
            setName: draft.setName,
            dexId: draft.dexId,
            pokemonDisplayName: draft.pokemonDisplayName,
            completionMode: selectedMode
        )
        Haptics.success()
        progressTracker.add(target)
        onChange()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            step = .manage
        }
        setQuery = ""
        pokemonQuery = ""
    }
}
