//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct PillView: View {
    @ObservedObject var context: PillContext
    /// callback triggerd by changes in the display text
    let didChangeText: () -> Void
    
    var textColor: Color {
        context.viewState.isOwnMention ? .compound.textBadgeAccent : .compound.textOnSolidPrimary
    }
    
    var backgroundColor: Color {
        context.viewState.isOwnMention ? .compound.bgBadgeAccent : .compound.bgBadgePrimary
    }
    
    var body: some View {
        mainContent
            .onChange(of: context.viewState.displayText) {
                didChangeText()
            }
    }
    
    private var mainContent: some View {
        HStack(spacing: 4) {
            Text(context.viewState.displayText)
                .lineLimit(1)
            
            if let emoji = context.viewState.statusEmoji {
                Text(String(emoji))
            }
        }
        .font(.compound.bodyLGSemibold)
        .foregroundColor(textColor)
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 1)
        .background(backgroundColor, in: .capsule)
    }
}
