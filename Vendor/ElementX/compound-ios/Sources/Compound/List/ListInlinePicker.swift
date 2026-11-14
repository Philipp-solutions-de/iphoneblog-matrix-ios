//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct ListInlinePicker<SelectedValue: Hashable>: View {
    let title: String?
    @Binding var selection: SelectedValue
    let items: [(title: String, tag: SelectedValue)]
    let isWaiting: Bool
    
    var body: some View {
        ForEach(items, id: \.tag) { item in
            ListRow(label: .plain(title: item.title),
                    details: isWaiting ? .isWaiting(selection == item.tag) : nil,
                    kind: .selection(isSelected: !isWaiting ? selection == item.tag : false) {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        
                        withTransaction(transaction) {
                            selection = item.tag
                        }
                    })
        }
    }
}

// MARK: - Previews
