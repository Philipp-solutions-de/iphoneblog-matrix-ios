import SwiftUI

/// Placing a new profile picture (Thorsten, 2026-11-19): the person zooms and moves it inside
/// the squircle before it is saved. The upload is what the web app uploads (agreed with the web
/// session): a square JPEG at quality 0.85, 512 px, smaller sources at their own size but at
/// least 128 px, corners filled (the squircle is only a mask), no EXIF.
enum AvatarCrop {
    static let maxSide: CGFloat = 512
    static let minSide: CGFloat = 128
    static let maxZoom: CGFloat = 4

    /// The largest offset, in points of a square view of side `view`, that leaves no empty space.
    static func clamp(_ offset: CGSize, image: CGSize, zoom: CGFloat, view: CGFloat) -> CGSize {
        let fill = view / min(image.width, image.height) * zoom
        let spareX = max(0, (image.width * fill - view) / 2), spareY = max(0, (image.height * fill - view) / 2)
        return CGSize(width: min(spareX, max(-spareX, offset.width)), height: min(spareY, max(-spareY, offset.height)))
    }

    /// The square the person sees, in the picture's own points (orientation applied).
    static func visibleRect(image: CGSize, zoom: CGFloat, offset: CGSize, view: CGFloat) -> CGRect {
        let zoom = min(maxZoom, max(1, zoom))
        let offset = clamp(offset, image: image, zoom: zoom, view: view)
        let fill = view / min(image.width, image.height) * zoom
        let side = min(image.width, image.height) / zoom
        let center = CGPoint(x: image.width / 2 - offset.width / fill, y: image.height / 2 - offset.height / fill)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// The side of the upload in pixels: 512, the source's own pixels if fewer, never under 128.
    static func outputSide(visibleSide: CGFloat, scale: CGFloat) -> CGFloat {
        max(minSide, min(maxSide, (visibleSide * scale).rounded(.down)))
    }

    /// The upload: what is in the square, as a JPEG. Drawing the UIImage applies its orientation,
    /// and a fresh JPEG carries no EXIF or location.
    static func render(_ image: UIImage, zoom: CGFloat, offset: CGSize, view: CGFloat) -> (image: UIImage, jpeg: Data)? {
        let visible = visibleRect(image: image.size, zoom: zoom, offset: offset, view: view)
        let side = outputSide(visibleSide: visible.width, scale: image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // pixels, not points: at the screen's 3× this was 1536 px
        format.opaque = true
        let k = side / visible.width
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: -visible.minX * k, y: -visible.minY * k, width: image.size.width * k, height: image.size.height * k))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return nil }
        return (square, jpeg)
    }
}

/// The sheet: the picture under a squircle mask, pinch to zoom (1× to 4×), drag to move.
struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (UIImage, Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetAtStart: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height) - 48
                let fill = side / min(image.size.width, image.size.height) * zoom
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * fill, height: image.size.height * fill)
                        .offset(AvatarCrop.clamp(offset, image: image.size, zoom: zoom, view: side))
                    // Dimmed outside the squircle; the corners still go into the upload.
                    Rectangle().fill(.black.opacity(0.55))
                        .mask {
                            Rectangle().overlay { AvatarShape.of(side).frame(width: side, height: side).blendMode(.destinationOut) }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    AvatarShape.of(side).stroke(.white.opacity(0.8), lineWidth: 1)
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom = min(AvatarCrop.maxZoom, max(1, zoomAtStart * $0.magnification)) }
                            .onEnded { _ in
                                zoomAtStart = zoom
                                offset = AvatarCrop.clamp(offset, image: image.size, zoom: zoom, view: side)
                                offsetAtStart = offset
                            },
                        DragGesture()
                            .onChanged { offset = AvatarCrop.clamp(CGSize(width: offsetAtStart.width + $0.translation.width,
                                                                          height: offsetAtStart.height + $0.translation.height),
                                                                   image: image.size, zoom: zoom, view: side) }
                            .onEnded { _ in offsetAtStart = offset }
                    )
                )
                .accessibilityElement()
                .accessibilityLabel("Bildausschnitt")
                .accessibilityIdentifier("avatar.crop")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", action: onCancel).accessibilityIdentifier("avatar.cropCancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            if let result = AvatarCrop.render(image, zoom: zoom, offset: offset, view: side) {
                                onSave(result.image, result.jpeg)
                            }
                        }
                        .accessibilityIdentifier("avatar.cropSave")
                    }
                }
            }
            .navigationTitle("Profilbild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
