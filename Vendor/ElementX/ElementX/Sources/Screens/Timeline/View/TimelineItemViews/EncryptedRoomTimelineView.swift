//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct EncryptedRoomTimelineView: View {
    let timelineItem: EncryptedRoomTimelineItem
    
    var icon: KeyPath<CompoundIcons, Image> {
        switch timelineItem.encryptionType {
        case .megolmV1AesSha2(_, let cause):
            switch cause {
            case .unknown:
                return \.time
            case .sentBeforeWeJoined,
                 .historicalMessageAndBackupDisabled,
                 .historicalMessageAndDeviceIsUnverified,
                 .verificationViolation,
                 .insecureDevice,
                 .witheldBySender,
                 .withheldForUnverifiedOrInsecureDevice:
                return \.block
            }
        default:
            return \.time
        }
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            Label(timelineItem.body, icon: icon, iconSize: .small, relativeTo: .compound.bodyLG)
                .labelStyle(RoomTimelineViewPlaceholderLabelStyle())
                .font(.compound.bodyLG)
        }
    }
}

struct RoomTimelineViewPlaceholderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon
                .foregroundColor(.compound.iconSecondary)
            configuration.title
                .font(.compound.bodyLG.italic())
                .foregroundColor(.compound.textSecondary)
        }
        .padding(.horizontal, 4)
    }
}
