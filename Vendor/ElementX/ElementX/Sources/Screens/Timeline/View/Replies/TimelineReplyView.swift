//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

enum TimelineReplyViewPlacement {
    case timeline
    case composer
}

struct TimelineReplyView: View {
    @Environment(\.timelineContext) private var timelineContext
    
    // periphery:ignore - might be useful to have
    let placement: TimelineReplyViewPlacement
    let timelineItemReplyDetails: TimelineItemReplyDetails?
    var maxWidth: CGFloat?
    
    var body: some View {
        ContentScanningView(contentScannerService: timelineContext?.contentScannerService,
                            mediaSource: scannedMediaSource,
                            thumbnailSource: scannedThumbnailSource,
                            containerShowsFailure: false) {
            content
                .roundedContainer(padding: 4,
                                  maxWidth: maxWidth,
                                  backgroundColor: .compound.bgCanvasDefault,
                                  borderColor: .compound.separatorPrimary)
        } scanningContent: {
            LoadingReplyView()
                .roundedContainer(padding: 4,
                                  maxWidth: maxWidth,
                                  backgroundColor: .compound.bgCanvasDefault,
                                  borderColor: .compound.separatorPrimary)
        } unsafeContent: { failure in
            ContentScanningFailureView(failure: failure)
                .roundedContainer(padding: 8,
                                  maxWidth: maxWidth,
                                  backgroundColor: .compound.bgCriticalSubtle,
                                  borderColor: .compound.borderCriticalSubtle)
        }
    }
    
    /// The media source validated by the content scanner when the replied to message contains media.
    private var scannedMediaSource: MediaSourceProxy? {
        guard case .loaded(_, _, let eventContent) = timelineItemReplyDetails,
              case .message(let message) = eventContent else {
            return nil
        }
        
        switch message {
        case .audio(let content): return content.source
        case .file(let content): return content.source
        case .image(let content): return content.imageInfo.source
        case .video(let content): return content.videoInfo.source
        case .voice(let content): return content.source
        // Only the first item is scanned as it's the only one the reply previews.
        case .gallery(let content): return content.items.first?.mediaSource
        default: return nil
        }
    }
    
    /// The thumbnail source validated alongside ``scannedMediaSource`` when the replied to message has one.
    private var scannedThumbnailSource: MediaSourceProxy? {
        guard case .loaded(_, _, let eventContent) = timelineItemReplyDetails,
              case .message(let message) = eventContent else {
            return nil
        }
        
        switch message {
        case .file(let content): return content.thumbnailSource
        case .image(let content): return content.thumbnailInfo?.source
        case .video(let content): return content.thumbnailInfo?.source
        case .gallery(let content): return content.items.first?.thumbnailSource
        default: return nil
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if let timelineItemReplyDetails {
            switch timelineItemReplyDetails {
            case .loaded(let sender, _, let content):
                switch content {
                case .message(let content):
                    switch content {
                    case .audio(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: .init(kind: .icon(\.audio)))
                    case .emote(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: content.formattedBody)
                    case .file(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: .init(kind: .icon(\.attachment)))
                    case .image(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: .init(kind: .mediaSource(content.thumbnailInfo?.source ?? content.imageInfo.source)))
                    case .notice(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: content.formattedBody)
                    case .text(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: content.formattedBody)
                    case .video(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: content.thumbnailInfo.map { .init(kind: .mediaSource($0.source)) })
                    case .voice:
                        ReplyView(sender: sender,
                                  plainBody: L10n.commonVoiceMessage,
                                  formattedBody: nil,
                                  icon: .init(kind: .icon(\.micOn)))
                    case .location:
                        ReplyView(sender: sender,
                                  plainBody: L10n.commonSharedLocation,
                                  formattedBody: nil,
                                  icon: .init(kind: .icon(\.locationPin)))
                    case .gallery(let content):
                        GalleryReplyView(sender: sender, content: content)
                    }
                case .poll(let question):
                    ReplyView(sender: sender,
                              plainBody: question,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.polls)))
                case .liveLocation:
                    ReplyView(sender: sender,
                              plainBody: L10n.commonSharedLiveLocation,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.locationPin)))
                case .redacted:
                    ReplyView(sender: sender,
                              plainBody: L10n.commonMessageRemoved,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.delete)))
                }
            default:
                LoadingReplyView()
            }
        }
    }
    
    /// A gallery previews its first attachment as though it had been sent on its own, counting its
    /// media when they're all images/videos and its attachments otherwise.
    private struct GalleryReplyView: View {
        let sender: TimelineItemSender
        let content: GalleryRoomTimelineItemContent
        
        private var caption: String? {
            content.caption?.isBlank == false ? content.caption : nil
        }
        
        private var isMediaGallery: Bool {
            content.items.allSatisfy { $0.isImage || $0.isVideo }
        }
        
        private var placeholder: String {
            if isMediaGallery {
                L10n.commonGalleryReplyMediaItems(content.items.count)
            } else {
                L10n.commonGalleryReplyAttachments(content.items.count)
            }
        }
        
        private var icon: ReplyView.Icon? {
            guard let item = content.items.first else { return nil }
            
            return switch item {
            case .image(_, let itemContent): .init(kind: .mediaSource(itemContent.thumbnailInfo?.source ?? itemContent.imageInfo.source))
            case .video(_, let itemContent): itemContent.thumbnailInfo.map { .init(kind: .mediaSource($0.source)) }
            case .audio: .init(kind: .icon(\.audio))
            case .file, .other: .init(kind: .icon(\.attachment))
            }
        }
        
        var body: some View {
            ReplyView(sender: sender,
                      plainBody: caption ?? placeholder,
                      formattedBody: caption == nil ? nil : content.formattedCaption,
                      icon: icon)
        }
    }
    
    private struct LoadingReplyView: View {
        var body: some View {
            ReplyView(sender: .init(id: "@alice:matrix.org"), plainBody: "Hello world", formattedBody: nil)
                .redacted(reason: .placeholder)
                .accessibilityLabel(L10n.commonLoading)
        }
    }
    
    private struct ReplyView: View {
        struct Icon {
            enum Kind {
                case mediaSource(MediaSourceProxy)
                case iconAsset(ImageAsset)
                case icon(KeyPath<CompoundIcons, Image>)
            }
            
            let kind: Kind
            let cornerRadii = 4.0
        }
        
        @EnvironmentObject private var context: TimelineViewModel.Context
        @ScaledMetric private var imageContainerSize = 36.0
        
        let sender: TimelineItemSender
        let plainBody: String
        let formattedBody: AttributedString?
        
        var icon: Icon?
        
        var body: some View {
            HStack(spacing: 8) {
                iconView
                    .frame(width: imageContainerSize, height: imageContainerSize)
                    .foregroundColor(.compound.iconPrimary)
                    .background(Color.compound.bgSubtlePrimary)
                    .cornerRadius(icon?.cornerRadii ?? 0.0, corners: .allCorners)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sender.disambiguatedDisplayName ?? sender.id)
                        .font(.compound.bodySMSemibold)
                        .foregroundColor(.compound.textPrimary)
                        .accessibilityLabel(L10n.commonInReplyTo(sender.disambiguatedDisplayName ?? sender.id))
                    
                    Text(context.viewState.buildMessagePreview(formattedBody: formattedBody, plainBody: plainBody))
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textSecondary)
                        .tint(.compound.textLinkExternal)
                        .lineLimit(2)
                }
                .padding(.leading, icon == nil ? 8 : 0)
                .padding(.trailing, 8)
            }
            .accessibilityElement(children: .combine)
        }
        
        @ViewBuilder
        private var iconView: some View {
            if let icon {
                switch icon.kind {
                case .mediaSource(let mediaSource):
                    LoadableImage(mediaSource: mediaSource,
                                  size: .init(width: imageContainerSize,
                                              height: imageContainerSize),
                                  mediaProvider: context.mediaProvider) {
                        CompoundIcon(\.image)
                            .padding(4.0)
                    }
                    .scaledToFill()
                case .iconAsset(let asset):
                    Image(asset: asset)
                        .resizable()
                        .scaledToFit()
                        .padding(8.0)
                case .icon(let keyPath):
                    CompoundIcon(keyPath, size: .medium, relativeTo: .body)
                }
            }
        }
    }
}

private extension View {
    /// Styles the view as a rounded container with a background fill and a border.
    func roundedContainer(padding: CGFloat = 12,
                          maxWidth: CGFloat? = nil,
                          backgroundColor: Color,
                          borderColor: Color) -> some View {
        let backgroundShape = RoundedRectangle(cornerRadius: 8)
        return fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(padding)
            .background {
                ZStack {
                    backgroundShape.fill(backgroundColor)
                    backgroundShape.stroke(borderColor)
                }
            }
    }
}
