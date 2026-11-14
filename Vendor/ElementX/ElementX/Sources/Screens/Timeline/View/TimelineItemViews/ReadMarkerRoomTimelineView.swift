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
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(L10n.screenRoomTimelineReadMarkerTitle)
                .textCase(.uppercase)
                .font(.compound.bodyXSSemibold)
                .foregroundColor(.compound.textActionAccent)
            
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.compound.borderAccentPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
