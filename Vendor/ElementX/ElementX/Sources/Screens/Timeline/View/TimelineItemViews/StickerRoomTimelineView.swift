//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

struct StickerRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: StickerRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            ContentScanningView(contentScannerService: context?.contentScannerService,
                                mediaSource: timelineItem.imageInfo.source) {
                LoadableImage(mediaSource: timelineItem.imageInfo.source,
                              mediaType: .timelineItem(uniqueID: timelineItem.id.uniqueID),
                              blurhash: timelineItem.blurhash,
                              size: timelineItem.imageInfo.size,
                              mediaProvider: context?.mediaProvider) {
                    placeholder
                }
                .timelineMediaFrame(imageInfo: timelineItem.imageInfo)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(L10n.commonSticker), \(timelineItem.body)")
                .onTapGesture {
                    context?.send(viewAction: .mediaTapped(itemID: timelineItem.id))
                }
            } scanningContent: {
                placeholder
                    .overlay { ProgressView() }
                    .timelineMediaFrame(imageInfo: timelineItem.imageInfo)
            } unsafeContent: { failure in
                ContentScanningFailureView(failure: failure)
            }
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundColor(timelineItem.isOutgoing ? .compound._bgBubbleOutgoing : .compound._bgBubbleIncoming)
            .opacity(0.3)
    }
}
