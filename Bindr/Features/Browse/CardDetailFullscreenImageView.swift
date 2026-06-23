import SwiftUI

struct CardDetailFullscreenImageView: View {
    let card: Card
    let onDismiss: () -> Void

    @State private var isPresented = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
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
            .offset(offset)
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.985)
            .offset(y: isPresented ? 0 : 8)
            .gesture(zoomGesture.simultaneously(with: panGesture))
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
                        action: dismissAnimated
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

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
                if scale <= 1 {
                    offset = .zero
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

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1 else {
                    resetTransform()
                    return
                }
                lastOffset = offset
            }
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func dismissAnimated() {
        withAnimation(.easeOut(duration: 0.18)) {
            isPresented = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }
}
