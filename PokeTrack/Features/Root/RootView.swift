import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var services = AppServices()
    @State private var selectedTab: AppTab = .browse

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List {
                        ForEach(AppTab.allCases) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Label(tab.title, systemImage: tab.symbolName)
                            }
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                        }
                    }
                    .navigationTitle("PokeTrack")
                } detail: {
                    NavigationStack {
                        tabView(for: selectedTab)
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    ForEach(AppTab.allCases) { tab in
                        NavigationStack {
                            tabView(for: tab)
                        }
                        .tabItem {
                            Label(tab.title, systemImage: tab.symbolName)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .environment(services)
        .task {
            await services.bootstrap()
        }
    }

    @ViewBuilder
    private func tabView(for tab: AppTab) -> some View {
        switch tab {
        case .browse:
            BrowseView()
        case .account:
            AccountView()
        }
    }
}

#Preview {
    RootView()
}
