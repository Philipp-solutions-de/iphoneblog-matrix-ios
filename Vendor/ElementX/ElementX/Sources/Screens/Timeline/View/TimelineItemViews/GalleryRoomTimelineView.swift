//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct GalleryRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: GalleryRoomTimelineItem
    
    private var hasMediaCaption: Bool {
        timelineItem.content.caption?.isBlank == false
    }
    
    // List layout when any item is non-visual (file/audio); a grid reads badly for documents.
    private var usesListLayout: Bool {
        timelineItem.content.items.contains { !$0.isImage && !$0.isVideo }
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            VStack(alignment: .leading, spacing: 8) {
                if usesListLayout {
                    GalleryListView(items: timelineItem.content.items,
                                    mediaProvider: context?.mediaProvider,
                                    contentScannerService: context?.contentScannerService,
                                    onItemTap: tap)
                } else {
                    GalleryGridView(items: timelineItem.content.items,
                                    mediaProvider: context?.mediaProvider,
                                    contentScannerService: context?.contentScannerService,
                                    onItemTap: tap)
                }
                
                if hasMediaCaption {
                    if usesListLayout {
                        GalleryDivider()
                    }
                    caption
                        .accessibilityHidden(true) // Announced when entering the gallery, so not a stop of its own.
                }
            }
            .frame(width: GalleryGridView.groupWidth, alignment: .leading)
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
    
    private func tap(index: Int) {
        context?.send(viewAction: .galleryItemTapped(.init(timelineItemID: timelineItem.id, mediaIndex: index)))
    }
}

// MARK: - Previews
