//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct ReadReceiptsSummaryView: View {
    let orderedReadReceipts: [ReadReceipt]
    @EnvironmentObject private var context: TimelineViewModel.Context
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.commonSeenBy)
                .font(.compound.bodyLGSemibold)
                .foregroundColor(.compound.textPrimary)
                .padding(.horizontal, 16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(orderedReadReceipts) { receipt in
                        ReadReceiptCell(readReceipt: receipt,
                                        memberState: context.viewState.members[receipt.userID],
                                        mediaProvider: context.mediaProvider)
                    }
                }
            }
        }
        .padding(.top, 24)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.compound.bgCanvasDefault)
        .presentationDragIndicator(.visible)
    }
}
