//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct TimelineReadReceiptsView: View {
    let displayNumber = 3
    let timelineItem: EventBasedTimelineItemProtocol
    @EnvironmentObject private var context: TimelineViewModel.Context
    
    var avatars: [StackedAvatarInfo] {
        timelineItem.properties.orderedReadReceipts.prefix(displayNumber).map { receipt in
            StackedAvatarInfo(url: context.viewState.members[receipt.userID]?.avatarURL,
                              name: context.viewState.members[receipt.userID]?.displayName,
                              contentID: receipt.userID)
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            StackedAvatarsView(overlap: 6,
                               lineWidth: 1,
                               avatars: avatars, avatarSize: .user(on: .readReceipt),
                               mediaProvider: context.mediaProvider)
                .padding(-1)
            if timelineItem.properties.orderedReadReceipts.count > displayNumber {
                Text("+\(remaining)")
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textPrimary)
            }
        }
        .onTapGesture {
            context.send(viewAction: .displayReadReceipts(itemID: timelineItem.id))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.a11yReadReceiptsTapToShowAllIos)
    }
    
    private var remaining: Int {
        timelineItem.properties.orderedReadReceipts.count - displayNumber
    }
    
    private var accessibilityLabel: String {
        if timelineItem.properties.orderedReadReceipts.count == 1 {
            return L10n.a11yReadReceiptsSingle(displayName(at: 0))
        } else if timelineItem.properties.orderedReadReceipts.count <= displayNumber {
            let limit = timelineItem.properties.orderedReadReceipts.count - 1
            let list = (0..<limit).map { displayName(at: $0) }.formatted(.list(type: .and, width: .narrow))
            let last = displayName(at: limit)
            return L10n.a11yReadReceiptsMultiple(list, last)
        } else if timelineItem.properties.orderedReadReceipts.count > displayNumber {
            let list = (0..<displayNumber).map { displayName(at: $0) }.formatted(.list(type: .and, width: .narrow))
            
            // Plurals with string arguments aren't generated correctly so we need to use this
            // https://github.com/SwiftGen/SwiftGen/issues/1089
            return L10n.tr("Localizable", "a11y_read_receipts_multiple_with_others", list, remaining)
        }
        return ""
    }
    
    private func displayName(at index: Int) -> String {
        let userID = timelineItem.properties.orderedReadReceipts[index].userID
        return context.viewState.members[userID]?.displayName ?? userID
    }
}
