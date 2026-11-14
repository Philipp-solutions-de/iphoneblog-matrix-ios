//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct NoticeRoomTimelineView: View, TextBasedRoomTimelineViewProtocol {
    let timelineItem: NoticeRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            // Spacing: 6 = label spacing - formatted text padding
            
            Label {
                if let attributedString = timelineItem.content.formattedBody {
                    FormattedBodyText(attributedString: attributedString,
                                      trailingReservedSize: timelineItem.trailingReservedSize)
                } else {
                    FormattedBodyText(text: timelineItem.content.body,
                                      trailingReservedSize: timelineItem.trailingReservedSize)
                }
            } icon: {
                CompoundIcon(\.info, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundColor(.compound.iconSecondary)
            }
            .labelStyle(.custom(spacing: 6.0, alignment: .top))
            .padding(.leading, 4) // Trailing padding is provided by FormattedBodyText
        }
    }
}
