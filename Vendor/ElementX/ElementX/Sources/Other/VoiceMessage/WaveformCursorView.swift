//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct WaveformCursorView: View {
    var color: Color = .compound.iconAccentTertiary
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
    }
}
