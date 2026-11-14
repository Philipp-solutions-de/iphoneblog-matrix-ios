//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

struct AudioRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: AudioRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            MediaFileRoomTimelineContent(filename: timelineItem.content.filename,
                                         fileSize: timelineItem.content.fileSize,
                                         caption: timelineItem.content.caption,
                                         formattedCaption: timelineItem.content.formattedCaption,
                                         trailingReservedSize: timelineItem.trailingReservedSize,
                                         shouldBoost: timelineItem.shouldBoost,
                                         isAudioFile: true,
                                         contentScannerService: context?.contentScannerService,
                                         mediaSource: timelineItem.content.source) {
                context?.send(viewAction: .mediaTapped(itemID: timelineItem.id))
            }
            .accessibilityLabel(L10n.commonAudio)
        }
    }
}
