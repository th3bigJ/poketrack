import SwiftUI

private enum BrowseFullScreen: String, Identifiable, Hashable {
    case allSets
    case allPokemon
    var id: String { rawValue }
}

/// Presents Browse Sets / Pokémon as one root `fullScreenCover`, and card detail in a **nested** cover so SwiftUI never stacks two root-level full-screen presentations (which triggers “only presenting a single sheet is supported”).
private struct BrowseFullScreenHost: View {
    let route: BrowseFullScreen
    @Environment(AppServices.self) private var services
    @State private var presentedCardPresentation: CardPresentationContext?

    var body: some View {
        NavigationStack {
            switch route {
            case .allSets:
                BrowseAllSetsView()
            case .allPokemon:
                BrowseAllPokemonView()
            }
        }
        .environment(\.presentCard, { card, list in
            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
            presentedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
        })
        .fullScreenCover(item: $presentedCardPresentation) { ctx in
            CardBrowseDetailView(cards: ctx.cards, startIndex: ctx.startIndex)
                .environment(services)
        }
    }
}

struct RootView: View {
    @State private var services = AppServices()
    @StateObject private var chromeScroll = ChromeScrollCoordinator()
    @State private var selectedTab: AppTab = .browse
    @State private var universalQuery = ""
    @State private var showCameraComingSoon = false
    @State private var showFilterComingSoon = false
    @State private var isSideMenuOpen = false
    @State private var isSearchExperiencePresented = false
    /// When non-empty, user has pushed card / set / dex from search — hide root `UniversalSearchBar` so detail matches Browse (back + title only).
    @State private var searchNavigationPath = NavigationPath()
    /// Title shown in the search-detail header when `searchNavigationPath` is non-empty.
    @State private var searchDetailTitle = ""
    /// Cards tab `NavigationStack` path — hide root chrome when a card detail (or other pushed screen) is showing.
    @State private var browseNavigationPath = NavigationPath()
    @State private var browseFullScreen: BrowseFullScreen?
    @State private var selectedCardPresentation: CardPresentationContext?
    @FocusState private var searchFieldFocused: Bool

    /// True when search has pushed into a detail view — swap the search bar for a back + title header.
    private var isSearchDetailActive: Bool {
        isSearchExperiencePresented && !searchNavigationPath.isEmpty
    }

    /// Search open at root list: show chrome. Search with a pushed detail: hide chrome. Cards tab with a pushed detail: hide chrome. Else scroll-driven chrome on Browse.
    private var showUniversalSearchBar: Bool {
        if isSideMenuOpen { return true }
        if isSearchExperiencePresented { return true }
        return chromeScroll.barsVisible
    }

    /// Screen-edge swipe to open the menu — only when no pushed `NavigationStack` screen and no full-screen browse (so it doesn’t compete with back / pop).
    private var isEdgeSwipeMenuEnabled: Bool {
        !isSideMenuOpen
            && browseNavigationPath.isEmpty
            && searchNavigationPath.isEmpty
            && browseFullScreen == nil
    }

    var body: some View {
        Group {
            if services.isReady {
                mainContent
            } else {
                LoadingScreen()
                    .task {
                        await services.bootstrap()
                    }
            }
        }
        .environment(services)
        .environmentObject(chromeScroll)
        .environment(\.presentCard, { card, list in
            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
        })
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let menuWidth = min(width * 0.65, 300)
            let searchBarTopInset = geo.safeAreaInsets.top + 8
            let edgeSwipeBelowSearchBar = geo.safeAreaInsets.top + 96
            ZStack(alignment: .leading) {
            SideMenuView(
                isPresented: $isSideMenuOpen,
                selectedTab: $selectedTab,
                headerTopPadding: searchBarTopInset,
                onPickSearch: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        searchFieldFocused = true
                    }
                }
            )
            .frame(width: menuWidth)
            .frame(maxHeight: .infinity)
            .zIndex(0)

            VStack(spacing: 0) {
                Group {
                    if isSearchDetailActive {
                        // Back + title header shown when user has drilled into a search result.
                        HStack(spacing: 4) {
                            Button {
                                searchNavigationPath = NavigationPath()
                                searchFieldFocused = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 17, weight: .semibold))
                                    Text("Search")
                                        .font(.system(size: 17, weight: .regular))
                                }
                                .foregroundStyle(.primary)
                                .padding(.leading, 8)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text(searchDetailTitle)
                                .font(.headline)
                                .lineLimit(1)
                                .padding(.trailing, 16)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if showUniversalSearchBar {
                        UniversalSearchBar(
                            text: $universalQuery,
                            isFocused: $searchFieldFocused,
                            isMenuOpen: isSideMenuOpen,
                            isSearchOpen: isSearchExperiencePresented,
                            onBurgerTap: {
                                if isSearchExperiencePresented {
                                    searchNavigationPath = NavigationPath()
                                    universalQuery = ""
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        isSearchExperiencePresented = false
                                    }
                                    searchFieldFocused = false
                                    return
                                }
                                searchFieldFocused = false
                                isSearchExperiencePresented = false
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    isSideMenuOpen.toggle()
                                }
                            },
                            onCamera: {
                                searchFieldFocused = false
                                showCameraComingSoon = true
                            },
                            onFilter: {
                                searchFieldFocused = false
                                showFilterComingSoon = true
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: chromeScroll.barsVisible)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSideMenuOpen)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSearchExperiencePresented)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSearchDetailActive)
                .clipped()

                ZStack(alignment: .top) {
                    TabView(selection: $selectedTab) {
                        ForEach(AppTab.allCases) { tab in
                            Group {
                                switch tab {
                                case .browse:
                                    NavigationStack(path: $browseNavigationPath) {
                                        BrowseView()
                                    }
                                case .account:
                                    NavigationStack {
                                        AccountView()
                                    }
                                }
                            }
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .tabItem {
                                Label(tab.title, systemImage: tab.symbolName)
                            }
                            .tag(tab)
                        }
                    }
                    .allowsHitTesting(!isSideMenuOpen)

                    if isSearchExperiencePresented {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea(edges: .bottom)
                            .onTapGesture {
                                searchNavigationPath = NavigationPath()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    isSearchExperiencePresented = false
                                }
                                searchFieldFocused = false
                            }

                        NavigationStack(path: $searchNavigationPath) {
                            SearchExperienceView(
                                query: $universalQuery,
                                onBrowseSets: {
                                    searchNavigationPath = NavigationPath()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        isSearchExperiencePresented = false
                                    }
                                    searchFieldFocused = false
                                    browseFullScreen = .allSets
                                },
                                onBrowsePokemon: {
                                    searchNavigationPath = NavigationPath()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        isSearchExperiencePresented = false
                                    }
                                    searchFieldFocused = false
                                    browseFullScreen = .allPokemon
                                }
                            )
                            .navigationDestination(for: SearchNavRoot.self) { root in
                                switch root {
                                case .set(let s):
                                    SetCardsView(set: s)
                                        .navigationBarBackButtonHidden(true)
                                        .toolbar(.hidden, for: .navigationBar)
                                        .onAppear {
                                            searchDetailTitle = s.name
                                            searchFieldFocused = false
                                        }
                                case .dex(let dexId, let displayName):
                                    DexCardsView(dexId: dexId, displayName: displayName)
                                        .navigationBarBackButtonHidden(true)
                                        .toolbar(.hidden, for: .navigationBar)
                                        .onAppear {
                                            searchDetailTitle = displayName
                                            searchFieldFocused = false
                                        }
                                }
                            }
                        }
                        .environment(\.presentCard, { card, list in
                            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
                            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
                        })
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background {
                            if searchNavigationPath.isEmpty {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.regularMaterial)
                            }
                        }
                        .padding(.horizontal, searchNavigationPath.isEmpty ? 12 : 0)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                        .allowsHitTesting(!isSideMenuOpen)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: isSearchExperiencePresented)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
            .offset(x: isSideMenuOpen ? menuWidth : 0)
            .shadow(
                color: .black.opacity(isSideMenuOpen ? 0.45 : 0),
                radius: 18,
                x: -10,
                y: 0
            )
            .overlay(alignment: .topLeading) {
                if isEdgeSwipeMenuEnabled {
                    LeftEdgeOpenMenuGesture(isEnabled: true) {
                        searchFieldFocused = false
                        searchNavigationPath = NavigationPath()
                        isSearchExperiencePresented = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            isSideMenuOpen = true
                        }
                    }
                    .frame(width: 28)
                    .padding(.top, edgeSwipeBelowSearchBar)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(400)
                }
            }
            .overlay(alignment: .trailing) {
                if isSideMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: max(0, width - menuWidth))
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea(edges: .vertical)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                isSideMenuOpen = false
                            }
                        }
                }
            }
            .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .onChange(of: searchFieldFocused) { _, isFocused in
            if isFocused {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    isSearchExperiencePresented = true
                }
            }
        }
        .onAppear {
            chromeScroll.configureForTab(selectedTab)
        }
        .onChange(of: selectedTab) { _, tab in
            chromeScroll.configureForTab(tab)
        }
        .onChange(of: browseNavigationPath.count) { _, newCount in
            if newCount == 0 {
                chromeScroll.forceVisible()
            }
        }
        .onChange(of: isSideMenuOpen) { _, open in
            if open { chromeScroll.forceVisible() }
        }
        .onChange(of: isSearchExperiencePresented) { _, open in
            if open {
                chromeScroll.forceVisible()
            } else {
                searchNavigationPath = NavigationPath()
            }
        }
        .fullScreenCover(item: $selectedCardPresentation) { ctx in
            CardBrowseDetailView(cards: ctx.cards, startIndex: ctx.startIndex)
                .environment(services)
        }
        .fullScreenCover(item: $browseFullScreen) { route in
            BrowseFullScreenHost(route: route)
                .environment(services)
        }
        .alert("Camera search", isPresented: $showCameraComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Visual search from the camera will be available in a future update.")
        }
        .alert("Filters", isPresented: $showFilterComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Filter controls will be available in a future update.")
        }
    }
}

#Preview {
    RootView()
}
