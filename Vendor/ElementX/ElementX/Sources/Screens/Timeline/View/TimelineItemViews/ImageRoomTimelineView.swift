//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

struct ImageRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: ImageRoomTimelineItem
    
    @State private var contentScanningFailure: ContentScanningFailure?
    
    var hasMediaCaption: Bool {
        timelineItem.content.caption != nil
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            // The caption sits 8pts below the content scanner failure placeholder, 4pts below the media.
            VStack(alignment: .leading, spacing: contentScanningFailure == nil ? 4 : 8) {
                ContentScanningView(contentScannerService: context?.contentScannerService,
                                    mediaSource: timelineItem.content.imageInfo.source,
                                    thumbnailSource: timelineItem.content.thumbnailInfo?.source) {
                    loadableImage
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.commonImage)
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
                        .timelineMediaFrame(imageInfo: timelineItem.content.thumbnailInfo ?? timelineItem.content.imageInfo)
                } unsafeContent: { failure in
                    ContentScanningFailureView(failure: failure)
                }
                
                caption
            }
            .onPreferenceChange(ContentScanningFailurePreferenceKey.self) { contentScanningFailure = $0 }
        }
    }
    
    @ViewBuilder
    private var caption: some View {
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
    
    @ViewBuilder
    private var loadableImage: some View {
        if timelineItem.content.contentType == .gif {
            LoadableImage(mediaSource: timelineItem.content.imageInfo.source,
                          mediaType: .timelineItem(uniqueID: timelineItem.id.uniqueID),
                          blurhash: timelineItem.content.blurhash,
                          size: timelineItem.content.imageInfo.size,
                          mediaProvider: context?.mediaProvider) {
                placeholder
            }
            .timelineMediaFrame(imageInfo: timelineItem.content.imageInfo)
        } else {
            LoadableImage(mediaSource: timelineItem.content.thumbnailInfo?.source ?? timelineItem.content.imageInfo.source,
                          mediaType: .timelineItem(uniqueID: timelineItem.id.uniqueID),
                          blurhash: timelineItem.content.blurhash,
                          size: timelineItem.content.thumbnailInfo?.size ?? timelineItem.content.imageInfo.size,
                          mediaProvider: context?.mediaProvider) {
                placeholder
            }
            .timelineMediaFrame(imageInfo: timelineItem.content.thumbnailInfo ?? timelineItem.content.imageInfo)
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundColor(timelineItem.isOutgoing ? .compound._bgBubbleOutgoing : .compound._bgBubbleIncoming)
            .opacity(0.3)
    }
}
