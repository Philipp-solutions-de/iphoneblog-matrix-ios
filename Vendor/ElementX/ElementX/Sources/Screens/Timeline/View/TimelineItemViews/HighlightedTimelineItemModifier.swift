//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

extension View {
    func highlightedTimelineItem(_ isHighlighted: Bool) -> some View {
        modifier(HighlightedTimelineItemModifier(isHighlighted: isHighlighted))
    }
}

private struct HighlightedTimelineItemModifier: ViewModifier {
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(.top, isHighlighted ? 1 : 0)
            .background {
                if isHighlighted {
                    VStack(spacing: 0) {
                        Color.compound.gradientSubtleStop1
                        LinearGradient(gradient: .compound.subtle,
                                       startPoint: .top,
                                       endPoint: .bottom)
                            .frame(maxHeight: 200)
                            .layoutPriority(1)
                    }
                    .overlay(alignment: .top) {
                        Color.compound.borderAccentSubtle
                            .frame(height: 1)
                    }
                }
            }
    }
}

// MARK: - Previews

// swiftlint:disable line_length blanket_disable_command
