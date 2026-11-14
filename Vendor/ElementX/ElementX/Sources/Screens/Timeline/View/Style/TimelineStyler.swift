//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

// MARK: - TimelineStyler

struct TimelineStyler<Content: View>: View {
    let timelineItem: EventBasedTimelineItemProtocol
    @ViewBuilder let content: () -> Content
    
    @State private var adjustedDeliveryStatus: TimelineItemDeliveryStatus?
    @State private var task: Task<Void, Never>?
    
    init(timelineItem: EventBasedTimelineItemProtocol, @ViewBuilder content: @escaping () -> Content) {
        self.timelineItem = timelineItem
        self.content = content
        _adjustedDeliveryStatus = State(initialValue: timelineItem.properties.deliveryStatus)
    }
    
    var body: some View {
        mainContent
            .onChange(of: timelineItem.properties.deliveryStatus) { _, newStatus in
                if case .sendingFailed = newStatus {
                    guard task == nil else {
                        return
                    }
                    task = Task {
                        // Add a short delay so that an immediate failure when retrying
                        // shows as sending for long enough to be visible to the user.
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled {
                            adjustedDeliveryStatus = newStatus
                        }
                        task = nil
                    }
                } else {
                    task?.cancel()
                    task = nil
                    adjustedDeliveryStatus = newStatus
                }
            }
            .animation(.elementDefault, value: adjustedDeliveryStatus)
    }
    
    var mainContent: some View {
        // iphoneblog: rows in the design's Slack style instead of bubbles (Shim/TimelineRowStyler.swift).
        TimelineItemRowStylerView(timelineItem: timelineItem, adjustedDeliveryStatus: adjustedDeliveryStatus, content: content)
    }
}
