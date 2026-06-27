import SwiftUI

/// Horizontally scrolling filter chips for the universal search overlay.
struct SearchCategoryChipBar: View {
    @Binding var selection: SearchScopeCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SearchScopeCategory.allCases) { category in
                    scopeChip(for: category)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func scopeChip(for category: SearchScopeCategory) -> some View {
        let isSelected = selection == category
        return Button {
            guard selection != category else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                selection = category
            }
            Haptics.selectionChanged()
        } label: {
            Text(category.title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .browsePillTabChipStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
