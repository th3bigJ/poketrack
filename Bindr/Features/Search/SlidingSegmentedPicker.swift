import SwiftUI

/// A premium, sliding-highlight segmented picker that respects the user's theme accent color.
/// Replaces the "bland grey" system segmented control with a custom glass-morphic version.
struct SlidingSegmentedPicker<SelectionValue: Hashable & Identifiable>: View {
    @Binding var selection: SelectionValue
    let items: [SelectionValue]
    let title: (SelectionValue) -> String
    
    @Environment(AppServices.self) private var services
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = selection == item
                
                Button {
                    if selection != item {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selection = item
                        }
                        Haptics.lightImpact()
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.7))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(services.theme.accentColor)
                                    .matchedGeometryEffect(id: "highlight", in: namespace)
                                    .shadow(color: services.theme.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }
}
