//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

struct EmoteRoomTimelineView: View, TextBasedRoomTimelineViewProtocol {
    let timelineItem: EmoteRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            if let attributedString = timelineItem.content.formattedBody {
                FormattedBodyText(attributedString: attributedString,
                                  trailingReservedSize: timelineItem.trailingReservedSize)
            } else {
                FormattedBodyText(text: timelineItem.content.body,
                                  trailingReservedSize: timelineItem.trailingReservedSize)
            }
        }
    }
}
