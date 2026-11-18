//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import Kingfisher
import SwiftUI

/// Used to configure animations
enum LoadableImageMediaType: Equatable {
    /// An avatar (can be displayed anywhere within the app).
    case avatar
    /// An image displayed in the timeline.
    case timelineItem(uniqueID: TimelineItemIdentifier.UniqueID)
    /// Any other media (can be displayed anywhere within the app).
    case generic
}

struct LoadableImage<TransformerView: View, PlaceholderView: View>: View {
    private let mediaSource: MediaSourceProxy?
    private let mediaType: LoadableImageMediaType
    private let blurhash: String?
    private let size: CGSize?
    private let mediaProvider: MediaProviderProtocol?
    private let transformer: (AnyView) -> TransformerView
    private let placeholder: () -> PlaceholderView
    
    /// A SwiftUI view that automatically fetches images
    /// It will try fetching the image from in-memory cache and if that's not available
    /// it will fire a task to load it through the image provider
    /// - Parameters:
    ///   - mediaSource: the source of the image
    ///   - blurhash: an optional blurhash
    ///   - transformer: entry point for configuring the resulting image view
    ///   - placeholder: a view to show while the image or blurhash are not available
    init(mediaSource: MediaSourceProxy,
         mediaType: LoadableImageMediaType = .generic,
         blurhash: String? = nil,
         size: CGSize? = nil,
         mediaProvider: MediaProviderProtocol?,
         transformer: @escaping (AnyView) -> TransformerView = { $0 },
         placeholder: @escaping () -> PlaceholderView) {
        self.mediaSource = mediaSource
        self.mediaType = mediaType
        self.blurhash = blurhash
        self.size = size
        self.mediaProvider = mediaProvider
        self.transformer = transformer
        self.placeholder = placeholder
    }
    
    init(url: URL,
         mediaType: LoadableImageMediaType = .generic,
         blurhash: String? = nil,
         size: CGSize? = nil,
         mediaProvider: MediaProviderProtocol?,
         transformer: @escaping (AnyView) -> TransformerView = { $0 },
         placeholder: @escaping () -> PlaceholderView) {
        mediaSource = try? MediaSourceProxy(url: url, mimeType: nil)
        self.mediaType = mediaType
        self.blurhash = blurhash
        self.size = size
        self.mediaProvider = mediaProvider
        self.transformer = transformer
        self.placeholder = placeholder
    }
    
    var body: some View {
        if let mediaSource {
            LoadableImageContent(mediaSource: mediaSource,
                                 mediaType: mediaType,
                                 blurhash: blurhash,
                                 size: size,
                                 mediaProvider: mediaProvider,
                                 transformer: transformer,
                                 placeholder: placeholder)
                .id(stableMediaIdentifier)
        } else {
            placeholder()
        }
    }
    
    private var stableMediaIdentifier: String? {
        switch mediaType {
        case .timelineItem(let uniqueID):
            // Consider media for the same item to be the same view
            uniqueID.value
        default:
            // Binds the lifecycle of the LoadableImage to the associated URL.
            // This fixes the problem of the cache returning old values after a change in the URL.
            mediaSource?.url.absoluteString
        }
    }
}

private struct LoadableImageContent<TransformerView: View, PlaceholderView: View>: View, ImageDataProvider {
    @Environment(\.shouldAutomaticallyLoadImages) private var loadAutomatically
    
    private let mediaSource: MediaSourceProxy
    private let mediaType: LoadableImageMediaType
    private let blurhash: String?
    private let transformer: (AnyView) -> TransformerView
    private let placeholder: () -> PlaceholderView
    
    @StateObject private var contentLoader: ContentLoader
    @State private var loadManually = false
    
    init(mediaSource: MediaSourceProxy,
         mediaType: LoadableImageMediaType,
         blurhash: String? = nil,
         size: CGSize? = nil,
         mediaProvider: MediaProviderProtocol?,
         transformer: @escaping (AnyView) -> TransformerView,
         placeholder: @escaping () -> PlaceholderView) {
        assert(mediaProvider != nil, "Missing image provider, make sure one has been supplied to the view model.")
        
        self.mediaSource = mediaSource
        self.mediaType = mediaType
        self.blurhash = blurhash
        self.transformer = transformer
        self.placeholder = placeholder
        _contentLoader = StateObject(wrappedValue: ContentLoader(mediaSource: mediaSource, size: size, mediaProvider: mediaProvider))
    }
    
    var shouldRender: Bool {
        loadAutomatically || loadManually
    }
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch (contentLoader.content, shouldRender) {
            case (.image(let image), true):
                transformer(AnyView(Image(uiImage: image).resizable()))
            case (.gifData(let data), true):
                // iphoneblog: with Reduce Motion a GIF shows its first frame.
                if reduceMotion, let still = UIImage(data: data) {
                    transformer(AnyView(Image(uiImage: still).resizable()))
                } else {
                    transformer(AnyView(KFAnimatedImage(source: .provider(self))))
                }
            case (.none, _), (_, false):
                if let blurHashView {
                    if shouldRender {
                        transformer(blurHashView)
                    } else {
                        blurHashView
                    }
                } else {
                    placeholder().overlay { placeholderOverlay }
                }
            }
        }
        .animation(mediaType == .avatar ? .noAnimation : .elementDefault, value: contentLoader.content)
        .animation(.elementDefault, value: loadManually)
        .task(id: mediaSource.url.absoluteString + "\(shouldRender)") {
            // iphoneblog: a timeline item keeps this view (and its loader) from its local echo to
            // the event the server returns, so the loader must follow the new source: it kept the
            // local file, which can be gone by then, and never asked the server (Philip's own
            // picture in #bugs, 2026-11-18, only ever showed the blurhash).
            contentLoader.use(mediaSource)
            guard shouldRender, contentLoader.content == nil else {
                return
            }
            
            // iphoneblog: a failed load is tried again, not left as a blurhash for good.
            for delay in [2.0, 5.0, 15.0, 30.0] {
                await contentLoader.load()
                if contentLoader.content != nil || Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            await contentLoader.load()
        }
        #if DEBUG
        .overlay {
            // iphoneblog: for UI tests (RichMessagesUITests), whether a timeline picture has loaded.
            if case .timelineItem = mediaType {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier(contentLoader.content == nil ? "timeline-image.waiting" : "timeline-image.loaded")
            }
        }
        #endif
        .onDisappear {
            guard contentLoader.content == nil else {
                return
            }
            
            contentLoader.cancel()
        }
    }
    
    /// Note: Returns `AnyView` as this is what `transformer` expects.
    var blurHashView: AnyView? {
        if let blurhash,
           // Build a small blurhash image so that it's fast
           let image = UIImage(blurHash: blurhash, size: .init(width: 10.0, height: 10.0)) {
            return AnyView(Image(uiImage: image).resizable().overlay { blurHashOverlay })
        } else {
            return nil
        }
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    var placeholderOverlay: some View {
        switch mediaType {
        case .avatar, .generic:
            EmptyView()
        case .timelineItem:
            if shouldRender {
                ProgressView(L10n.commonLoading)
                    .frame(maxWidth: .infinity)
            } else {
                loadManuallyButton
            }
        }
    }
    
    @ViewBuilder
    var blurHashOverlay: some View {
        if !shouldRender {
            loadManuallyButton
        }
    }
    
    var loadManuallyButton: some View {
        ZStack {
            Color.black.opacity(0.6)
                .contentShape(.rect)
                .onTapGesture { /* Empty gesture to block the `mediaTapped` action */ }
            
            // Don't use a real Button as it sometimes triggers simultaneously with the long press gesture.
            Text(L10n.actionShow)
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.textOnSolidPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .overlay {
                    Capsule()
                        .stroke(lineWidth: 1)
                        .foregroundStyle(.compound.borderInteractiveSecondary)
                }
                .contentShape(.capsule)
                .onTapGesture {
                    loadManually = true
                }
                .environment(\.colorScheme, .light)
        }
    }
    
    // MARK: - ImageDataProvider
    
    nonisolated var cacheKey: String {
        mediaSource.url.absoluteString
    }
    
    nonisolated func data(handler: @escaping @Sendable (Result<Data, Error>) -> Void) {
        // Kingfisher isn't annotated and doesn't guarantee the provider is invoked on the main
        // thread so hop onto the main actor.
        Task { @MainActor in
            guard case let .gifData(data) = contentLoader.content else {
                handler(.failure(LoadableImageError.missingGIFData))
                return
            }
            
            handler(.success(data))
        }
    }
}

private enum LoadableImageError: Error {
    case missingGIFData
}

private class ContentLoader: ObservableObject {
    enum Content: Equatable {
        case image(UIImage)
        case gifData(Data)
    }
    
    private let mediaProvider: MediaProviderProtocol?
    private var mediaSource: MediaSourceProxy
    private let size: CGSize?
    private var imageLoadingCancellable: AnyCancellable?
    
    @Published private var cachedContent: Content?
    
    var content: Content? {
        if cachedContent != nil {
            return cachedContent
        }
        
        if isGIF {
            if let image = mediaProvider?.imageFromSource(mediaSource),
               let data = image.kf.data(format: .GIF) {
                return .gifData(data)
            }
        } else if let image = mediaProvider?.imageFromSource(mediaSource, size: size) {
            return .image(image)
        }
        
        return cachedContent
    }
    
    init(mediaSource: MediaSourceProxy, size: CGSize?, mediaProvider: MediaProviderProtocol?) {
        self.mediaSource = mediaSource
        self.size = size
        self.mediaProvider = mediaProvider
    }
    
    /// iphoneblog: the view's current source; a new one (the server's, after the local echo)
    /// replaces the old, and a load in flight for the old one is dropped.
    func use(_ source: MediaSourceProxy) {
        guard source.url != mediaSource.url else { return }
        imageLoadingCancellable?.cancel()
        mediaSource = source
    }
    
    func load() async {
        #if DEBUG
        // iphoneblog: UI tests make the local echo's copy fail to load, as it did on Philip's
        // iPhone. The SDK's send queue names it mxc://send-queue.localhost/… until the upload ends.
        if ProcessInfo.processInfo.environment["IPHONEBLOG_FAIL_LOCAL_MEDIA"] == "1",
           mediaSource.url.scheme != "mxc" || mediaSource.url.host()?.hasPrefix("send-queue") == true {
            return
        }
        #endif
        if isGIF {
            if case let .success(data) = await mediaProvider?.loadImageDataFromSource(mediaSource) {
                cachedContent = .gifData(data)
            }
        } else {
            guard let task = mediaProvider?.loadImageRetryingOnReconnection(mediaSource, size: size) else {
                MXLog.error("Failed loading image, invalid reconnection retry task.")
                return
            }
            
            imageLoadingCancellable = task.asCancellable()
            
            if let image = try? await task.value {
                cachedContent = .image(image)
            }
        }
    }
    
    func cancel() {
        imageLoadingCancellable?.cancel()
    }
    
    private var isGIF: Bool {
        mediaSource.mimeType == "image/gif"
    }
}

extension EnvironmentValues {
    /// Whether or not images should be loaded inside `LoadableImage` without a user interaction.
    @Entry var shouldAutomaticallyLoadImages = true
}

// MARK: - Previews

private extension View {
    func layout(title: String, hideTimelineMedia: Bool = false) -> some View {
        scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .bottom) {
                Text(title)
                    .font(.caption2)
                    .offset(y: 16)
                    .padding(.horizontal, -5)
            }
            .environment(\.shouldAutomaticallyLoadImages, !hideTimelineMedia)
    }
}
