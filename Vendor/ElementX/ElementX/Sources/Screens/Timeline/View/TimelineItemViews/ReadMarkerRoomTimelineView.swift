//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct ReadMarkerRoomTimelineView: View {
    // iphoneblog: the web's divider (v0.6.5): a teal line with "Neu" in the middle, above the
    // first unread message.
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.compound.borderAccentPrimary)
            Text(L10n.screenRoomTimelineReadMarkerTitle)
                .font(.compound.bodySMSemibold)
                .foregroundColor(.compound.textActionAccent)
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.compound.borderAccentPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.screenRoomTimelineReadMarkerTitle)
        .accessibilityIdentifier("timeline.readMarker")
    }
}
