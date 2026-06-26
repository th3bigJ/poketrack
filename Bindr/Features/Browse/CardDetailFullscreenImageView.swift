import SwiftUI

struct CardDetailFullscreenImageView: View {
    let card: Card
    let onDismiss: () -> Void

    @State private var isPresented = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissDragOffset: CGSize = .zero
    @State private var backdropOpacity: Double = 1
    @State private var imageOpacity: Double = 1

    private var isZoomed: Bool { scale > 1.05 }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: card.highResImageSrc),
                targetSize: CGSize(width: 1100, height: 1540)
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
            .scaleEffect(scale)
            .offset(combinedOffset)
            .opacity(isPresented ? imageOpacity : 0)
            .scaleEffect(isPresented ? 1 : 0.985)
            .offset(y: isPresented ? 0 : 8)
            .gesture(zoomGesture.simultaneously(with: dragGesture))
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    if scale > 1 {
                        resetTransform()
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    ChromeGlassCircleButton(
                        accessibilityLabel: "Close full screen card",
                        action: { dismissAnimated() }
                    ) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .environment(\.colorScheme, .dark)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Spacer()
            }
            .opacity(imageOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                isPresented = true
            }
        }
        .accessibilityAction(.escape) {
            dismissAnimated()
        }
    }

    private var combinedOffset: CGSize {
        if isZoomed {
            return offset
        }
        return dismissDragOffset
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
                if scale <= 1 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .onEnded { _ in
                if scale < 1.05 {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        resetTransform()
                    }
                } else {
                    lastScale = scale
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if isZoomed {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else {
                    dismissDragOffset = value.translation
                    let progress = min(1, dragDistance(value.translation) / 280)
                    backdropOpacity = 1 - progress * 0.45
                    imageOpacity = 1 - progress * 0.35
                }
            }
            .onEnded { value in
                if isZoomed {
                    lastOffset = offset
                    return
                }

                let distance = dragDistance(value.translation)
                let velocity = dragDistance(value.velocity)
                if distance > 100 || velocity > 600 {
                    dismissAnimated(from: value.translation)
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        dismissDragOffset = .zero
                        backdropOpacity = 1
                        imageOpacity = 1
                    }
                }
            }
    }

    private func dragDistance(_ size: CGSize) -> CGFloat {
        hypot(size.width, size.height)
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        dismissDragOffset = .zero
        backdropOpacity = 1
        imageOpacity = 1
    }

    private func dismissAnimated(from translation: CGSize = .zero) {
        let distance = dragDistance(translation)
        if distance > 8 {
            let angle = atan2(translation.height, translation.width)
            withAnimation(.easeOut(duration: 0.28)) {
                dismissDragOffset = CGSize(
                    width: cos(angle) * 420,
                    height: sin(angle) * 420
                )
                backdropOpacity = 0
                imageOpacity = 0
                isPresented = false
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                backdropOpacity = 0
                imageOpacity = 0
                isPresented = false
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            onDismiss()
        }
    }
}
