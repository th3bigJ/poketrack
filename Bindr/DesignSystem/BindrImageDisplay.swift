import SwiftUI

extension View {
    /// Rasterizes image content once so SwiftUI does not re-run ColorSync display matching every frame.
    ///
    /// Use on catalog thumbnails in scrolling grids — the main source of repeated
    /// `Invalid profile 'c2ci'` console noise on P3 displays.
    func bindrRasterizedForDisplay() -> some View {
        drawingGroup(opaque: false, colorMode: .nonLinear)
    }
}
