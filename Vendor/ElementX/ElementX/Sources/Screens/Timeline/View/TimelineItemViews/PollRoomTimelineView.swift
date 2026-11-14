//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct PollRoomTimelineView: View {
    let timelineItem: PollRoomTimelineItem
    @EnvironmentObject private var context: TimelineViewModel.Context
    
    private var state: PollViewState {
        if context.viewState.timelineKind == .pinned {
            return .preview
        } else {
            return .full(isEditable: timelineItem.isEditable)
        }
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            PollView(poll: poll,
                     state: state,
                     sender: timelineItem.sender) { action in
                switch action {
                case .sendResponse(let answerIDs):
                    guard let eventID else { return }
                    context.send(viewAction: .handlePollAction(.sendResponse(pollStartID: eventID, answerIDs: answerIDs)))
                case .edit:
                    guard let eventID else { return }
                    context.send(viewAction: .handlePollAction(.edit(pollStartID: eventID, poll: poll)))
                case .end:
                    guard let eventID else { return }
                    context.send(viewAction: .handlePollAction(.end(pollStartID: eventID)))
                }
            }
        }
    }
    
    // MARK: - Private
    
    private var poll: Poll {
        timelineItem.poll
    }
    
    private var eventID: String? {
        timelineItem.id.eventID
    }
}
