//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Images for the timeline, decoded and scaled before they reach the main thread
// (docs/performance.md, "What made it fast").
//
// Element X's MediaProvider turns the downloaded bytes into a UIImage with `UIImage(data:)` and
// hands that over undecoded. Core Animation then decodes it on the main thread the first time a
// row draws it, in the middle of a scroll: 2 to 4 ms for an 800x600 thumbnail, tens of ms for a
// photo that came without one, which a 120 Hz frame (8.3 ms) cannot absorb. With approachable
// concurrency, `UIImage(data:)` itself runs on the caller's actor too, which is the main actor.
//
// This wraps the provider without patching it:
// - the size a row asks for is capped at `maxPixels` on the long side, so a photo sent without
//   a thumbnail is fetched as a thumbnail the row can use, not as 12 megapixels;
// - the image is decoded, and scaled when it is still larger, in a detached task, and kept in
//   a cache of decoded images that `imageFromSource` answers from on the next draw.
// A request without a size (the full-screen viewer) passes through unchanged but decoded.

import Foundation
import UIKit

nonisolated final class PreparedMediaProvider: MediaProviderProtocol, @unchecked Sendable {
    /// The longest side, in pixels, a timeline row ever needs: 280 pt at 3x is 840.
    static let maxPixels: CGFloat = 1024

    private let base: MediaProviderProtocol
    private let prepared = NSCache<NSString, UIImage>()

    init(base: MediaProviderProtocol) {
        self.base = base
        prepared.totalCostLimit = 96 * 1024 * 1024
    }

    // MARK: Images

    func imageFromSource(_ source: MediaSourceProxy?, size: CGSize?) -> UIImage? {
        guard let source else { return nil }
        let size = Self.capped(size)
        if let image = prepared.object(forKey: key(source, size)) { return image }
        // Not decoded yet: let the row show its placeholder and load, rather than draw an
        // undecoded image from Element X's cache and decode it here.
        return nil
    }

    func loadImageRetryingOnReconnection(_ source: MediaSourceProxy, size: CGSize?) -> Task<UIImage, Error> {
        let size = Self.capped(size)
        let cacheKey = key(source, size)
        if let image = prepared.object(forKey: cacheKey) {
            return Task.detached { image }
        }
        let inner = base.loadImageRetryingOnReconnection(source, size: size)
        let cache = prepared
        return Task.detached(priority: .userInitiated) {
            let image = try await withTaskCancellationHandler {
                try await inner.value
            } onCancel: {
                inner.cancel()
            }
            let ready = await Self.prepare(image, fitting: size)
            cache.setObject(ready, forKey: cacheKey, cost: Self.cost(of: ready))
            return ready
        }
    }

    func loadImageDataFromSource(_ source: MediaSourceProxy) async -> Result<Data, MediaProviderError> {
        await base.loadImageDataFromSource(source)
    }

    func loadThumbnailForSource(source: MediaSourceProxy, size: CGSize) async -> Result<Data, MediaProviderError> {
        await base.loadThumbnailForSource(source: source, size: size)
    }

    func loadFileFromSource(_ source: MediaSourceProxy, filename: String?) async -> Result<MediaFileHandleProxy, MediaProviderError> {
        await base.loadFileFromSource(source, filename: filename)
    }

    // MARK: Decoding

    /// Decoded, and scaled down to `size` when it is larger, off the main thread.
    static func prepare(_ image: UIImage, fitting size: CGSize?) async -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        if let size, pixels.width > size.width * 1.2 || pixels.height > size.height * 1.2 {
            let ratio = min(size.width / pixels.width, size.height / pixels.height)
            let target = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
            if let thumbnail = await image.byPreparingThumbnail(ofSize: target) { return thumbnail }
        }
        return await image.byPreparingForDisplay() ?? image
    }

    /// A row's size capped at `maxPixels` on its long side, keeping the aspect ratio.
    static func capped(_ size: CGSize?) -> CGSize? {
        guard let size, size.width > 0, size.height > 0 else { return size }
        let longest = max(size.width, size.height)
        guard longest > maxPixels else { return size }
        let ratio = maxPixels / longest
        return CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private func key(_ source: MediaSourceProxy, _ size: CGSize?) -> NSString {
        let s = size.map { "{\($0.width),\($0.height)}" } ?? ""
        return (source.url.absoluteString + s) as NSString
    }
}
