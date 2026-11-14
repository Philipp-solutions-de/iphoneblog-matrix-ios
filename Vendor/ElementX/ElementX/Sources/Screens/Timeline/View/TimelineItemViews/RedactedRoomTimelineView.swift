//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

struct RedactedRoomTimelineView: View {
    let timelineItem: RedactedRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            Label(timelineItem.body, icon: \.delete, iconSize: .small, relativeTo: .compound.bodyLG)
                .labelStyle(RoomTimelineViewPlaceholderLabelStyle())
        }
    }
}
