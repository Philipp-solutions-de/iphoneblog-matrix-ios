//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct VideoRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: VideoRoomTimelineItem
    
    @State private var contentScanningFailure: ContentScanningFailure?
    
    private var hasMediaCaption: Bool {
        timelineItem.content.caption != nil
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            // The caption sits 8pts below the content scanner failure placeholder, 4pts below the media.
            VStack(alignment: .leading, spacing: contentScanningFailure == nil ? 4 : 8) {
                ContentScanningView(contentScannerService: context?.contentScannerService,
                                    mediaSource: timelineItem.content.videoInfo.source,
                                    thumbnailSource: timelineItem.content.thumbnailInfo?.source) {
                    thumbnail
                        .timelineMediaFrame(imageInfo: timelineItem.content.thumbnailInfo)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.commonVideo)
                        // This clip shape is distinct from the one in the styler as that one
                        // operates on the entire message so wouldn't round the bottom corners.
                        // iphoneblog: with a caption the row does not clip the whole item (the caption would lose
                        // its first letter, Philip 2026-11-20); the picture is rounded here, as without one.
                        .clipShape(RoundedRectangle(cornerRadius: hasMediaCaption ? ChatKitStyle.current.metrics.corner : 0, style: .continuous))
                        .onTapGesture {
                            context?.send(viewAction: .mediaTapped(itemID: timelineItem.id))
                        }
                } scanningContent: {
                    placeholder
                        .overlay { ProgressView() }
                        .timelineMediaFrame(imageInfo: timelineItem.content.thumbnailInfo)
                } unsafeContent: { failure in
                    ContentScanningFailureView(failure: failure)
                }
                
                if let attributedCaption = timelineItem.content.formattedCaption {
                    FormattedBodyText(attributedString: attributedCaption,
                                      trailingReservedSize: timelineItem.trailingReservedSize,
                                      boostFontSize: timelineItem.shouldBoost)
                } else if let caption = timelineItem.content.caption {
                    FormattedBodyText(text: caption,
                                      trailingReservedSize: timelineItem.trailingReservedSize,
                                      boostFontSize: timelineItem.shouldBoost)
                }
            }
            .onPreferenceChange(ContentScanningFailurePreferenceKey.self) { contentScanningFailure = $0 }
        }
    }
    
    @ViewBuilder
    var thumbnail: some View {
        if let thumbnailSource = timelineItem.content.thumbnailInfo?.source {
            LoadableImage(mediaSource: thumbnailSource,
                          mediaType: .timelineItem(uniqueID: timelineItem.id.uniqueID),
                          blurhash: timelineItem.content.blurhash,
                          size: timelineItem.content.thumbnailInfo?.size,
                          mediaProvider: context?.mediaProvider) { imageView in
                imageView
                    .overlay { playIcon }
            } placeholder: {
                placeholder
            }
        } else {
            playIcon
        }
    }
    
    var playIcon: some View {
        CompoundIcon(\.playSolid, size: .medium, relativeTo: .compound.headingLG)
            .foregroundStyle(.compound.iconPrimary)
            .padding(13)
            .background {
                ZStack {
                    Circle().fill(.compound.bgSubtleSecondary)
                    Circle().stroke(.compound.borderInteractiveSecondary)
                }
            }
    }
    
    var placeholder: some View {
        Rectangle()
            .foregroundStyle(timelineItem.isOutgoing ? .compound._bgBubbleOutgoing : .compound._bgBubbleIncoming)
            .opacity(0.3)
    }
}
