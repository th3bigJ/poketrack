import SwiftUI
import SwiftData

struct BindersRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \Binder.createdAt, order: .reverse) private var binders: [Binder]

    @Binding var showCreateSheet: Bool
    @State private var showPaywall = false
    @State private var binderToDelete: Binder?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if binders.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear.frame(height: rootFloatingChromeInset)
                        ContentUnavailableView {
                            Label("No Binders", systemImage: "books.vertical")
                        } description: {
                            Text("Create a binder to organise your cards.")
                        } actions: {
                            Button("Create a Binder") { handleCreateTap() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: rootFloatingChromeInset)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(binders) { binder in
                                NavigationLink(value: binder) {
                                    BinderCardCell(binder: binder)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        binderToDelete = binder
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete Binder", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Binder.self) { binder in
            BinderDetailView(binder: binder)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateBinderSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .confirmationDialog("Delete Binder?", isPresented: $showDeleteConfirm, presenting: binderToDelete) { binder in
            Button("Delete \"\(binder.title)\"", role: .destructive) {
                modelContext.delete(binder)
            }
            Button("Cancel", role: .cancel) {}
        } message: { binder in
            Text("This will permanently remove \"\(binder.title)\" and all its slots.")
        }
    }

    private func handleCreateTap() {
        if !services.store.isPremium && binders.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }
}

private struct BinderCardCell: View {
    let binder: Binder

    var body: some View {
        HStack(spacing: 0) {
            // Binder spine
            Rectangle()
                .fill(binderColor(binder.colour).opacity(0.55))
                .frame(width: 18)

            // Binder body
            ZStack(alignment: .bottomLeading) {
                binderColor(binder.colour).opacity(0.18)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(binder.title)
                        .font(.headline)
                        .foregroundStyle(binderColor(binder.colour))
                        .lineLimit(2)
                    Text("\(binder.slotList.count) cards")
                        .font(.caption)
                        .foregroundStyle(binderColor(binder.colour).opacity(0.7))
                }
                .padding(12)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(binderColor(binder.colour).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func binderColor(_ name: String) -> Color {
        switch name {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "pink":   return .pink
        default:       return Color(uiColor: .systemGray2)
        }
    }
}
