import SwiftUI

extension View {
    /// Kept as a named display hook for image-heavy views.
    /// Avoid forcing `drawingGroup` on scrolling thumbnails; it creates many
    /// offscreen render passes and makes grids feel capped at a low frame rate.
    func bindrRasterizedForDisplay() -> some View {
        self
    }
}
