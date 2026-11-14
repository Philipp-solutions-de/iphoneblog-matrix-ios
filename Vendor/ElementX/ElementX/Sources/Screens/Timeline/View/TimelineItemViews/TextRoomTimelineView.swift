//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import OrderedCollections
import SwiftUI

struct TextRoomTimelineView: View, TextBasedRoomTimelineViewProtocol {
    static let maxLinkPreviewsToRender = 2
    
    @Environment(\.timelineContext) private var context
    let timelineItem: TextRoomTimelineItem
    
    @State private var linkMetadata: OrderedDictionary<URL, LinkMetadataProviderItem>
    
    init(timelineItem: TextRoomTimelineItem, linkMetadata: OrderedDictionary<URL, LinkMetadataProviderItem> = [:]) {
        self.timelineItem = timelineItem
        self.linkMetadata = linkMetadata
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            VStack(alignment: .leading, spacing: 8) {
                if let attributedString = timelineItem.content.formattedBody {
                    FormattedBodyText(attributedString: attributedString,
                                      trailingReservedSize: timelineItem.trailingReservedSize,
                                      boostFontSize: timelineItem.shouldBoost)
                } else {
                    FormattedBodyText(text: timelineItem.body,
                                      trailingReservedSize: timelineItem.trailingReservedSize,
                                      boostFontSize: timelineItem.shouldBoost)
                }
                
                if context?.viewState.linkPreviewsEnabled ?? false, !linkMetadata.keys.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(linkMetadata.keys, id: \.absoluteString) { url in
                            let metadata = linkMetadata[url]?.metadata ?? context?.viewState.linkMetadataProvider?.metadataItems[url]?.metadata
                            LinkPreviewView(url: url, metadata: metadata)
                        }
                    }
                    // Link previews report the full proposed width, which would otherwise stretch the bubble across the timeline.
                    .frame(maxWidth: TimelineMediaFrame.maxLinkPreviewWidth)
                    .padding(.bottom, 16)
                }
            }
        }
        .task { await fetchLinkPreviews() }
    }
    
    private func fetchLinkPreviews() async {
        guard context?.viewState.linkPreviewsEnabled ?? false else {
            return
        }
        
        // Fetch the previews concurrently. The work stays on the main actor (the provider and
        // its LPLinkMetadata are main actor bound) but each network fetch suspends, so they still
        // overlap rather than running one after another.
        await withTaskGroup { taskGroup in
            for url in timelineItem.links.prefix(Self.maxLinkPreviewsToRender) {
                taskGroup.addTask {
                    await fetchLinkPreview(for: url)
                }
            }
        }
    }
    
    @MainActor
    private func fetchLinkPreview(for url: URL) async {
        if case let .success(metadata) = await context?.viewState.linkMetadataProvider?.fetchMetadataFor(url: url) {
            linkMetadata[url] = metadata
        }
    }
}
