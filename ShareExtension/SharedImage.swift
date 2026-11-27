import ImageIO
import UIKit
import UniformTypeIdentifiers

/// One shared picture, ready to upload: at most 2560 px on its long side, turned upright, and
/// written anew, so no metadata goes along (no location from the camera). A GIF stays as it is,
/// so it keeps moving; a PNG stays a PNG (screenshots), everything else becomes a JPEG.
struct SharedImage: Identifiable {
    let id = UUID()
    let data: Data
    let mimeType: String
    let fileName: String
    let width: Int
    let height: Int
    let preview: UIImage

    static let maxSide = 2560
    /// GIFs larger than this are written anew like any picture (still, but sendable).
    static let maxGIFBytes = 8 * 1024 * 1024

    static func load(from provider: NSItemProvider) async -> SharedImage? {
        let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
        let data: Data? = await withCheckedContinuation { done in
            _ = provider.loadDataRepresentation(for: type) { data, _ in done.resume(returning: data) }
        }
        guard let data else { return nil }
        return make(data: data, type: type)
    }

    static func make(data: Data, type: UTType) -> SharedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = thumbnail(source, maxSide: 240) else { return nil }
        if type.conforms(to: .gif), data.count <= maxGIFBytes,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int {
            return SharedImage(data: data, mimeType: "image/gif", fileName: "Bild.gif", width: width, height: height,
                               preview: UIImage(cgImage: preview))
        }
        guard let image = thumbnail(source, maxSide: maxSide) else { return nil }
        let png = type.conforms(to: .png)
        let out = NSMutableData()
        let outType = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(out, outType, 1, nil) else { return nil }
        let options: [CFString: Any] = png ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return SharedImage(data: out as Data, mimeType: png ? "image/png" : "image/jpeg",
                           fileName: png ? "Bild.png" : "Bild.jpg", width: image.width, height: image.height,
                           preview: UIImage(cgImage: preview))
    }

    /// The picture upright and no larger than `maxSide`, decoded at that size (a 48 MP photo
    /// is never decoded whole: the extension has little memory).
    private static func thumbnail(_ source: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
