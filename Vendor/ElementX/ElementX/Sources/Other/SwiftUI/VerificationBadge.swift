//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct VerificationBadge: View {
    let verificationState: UserIdentityVerificationState
    let size: CompoundIcon.Size
    let font: Font
    
    init(verificationState: UserIdentityVerificationState) {
        self.init(verificationState: verificationState, size: .small, relativeTo: .compound.bodyMD)
    }
    
    init(verificationState: UserIdentityVerificationState, size: CompoundIcon.Size, relativeTo font: Font) {
        self.verificationState = verificationState
        self.size = size
        self.font = font
    }
    
    var body: some View {
        switch verificationState {
        case .verified:
            CompoundIcon(\.verified, size: size, relativeTo: font)
                .foregroundStyle(.compound.iconSuccessPrimary)
        case .verificationViolation:
            CompoundIcon(\.infoSolid, size: size, relativeTo: font)
                .foregroundStyle(.compound.iconCriticalPrimary)
        case .notVerified:
            EmptyView()
        }
    }
}
