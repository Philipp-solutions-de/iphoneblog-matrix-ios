//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Element X reports usage to PostHog and timings to Sentry. Our app reports nothing: these
// stand-ins keep the calls in the vendored views and drop them. Only the event names come from
// matrix-analytics-events (Apache-2.0), so the call sites compile unchanged.

import AnalyticsEvents
import Foundation

protocol AnalyticsServiceProtocol {
    var signpost: Signposter { get }
    func trackInteraction(index: Int?, name: AnalyticsEvent.Interaction.Name)
    func trackComposer(inThread: Bool, isEditing: Bool, isReply: Bool,
                       messageType: AnalyticsEvent.Composer.MessageType, startsThread: Bool?)
    func trackPinUnpinEvent(_ event: AnalyticsEvent.PinUnpinAction)
    func trackPollVote()
    func trackPollEnd()
    func trackRoomModeration(action: AnalyticsEvent.RoomModeration.Action, role: RoomRole?)
}

extension AnalyticsServiceProtocol {
    func trackInteraction(name: AnalyticsEvent.Interaction.Name) {
        trackInteraction(index: nil, name: name)
    }

    func trackComposer(inThread: Bool, isEditing: Bool, isReply: Bool, startsThread: Bool?) {
        trackComposer(inThread: inThread, isEditing: isEditing, isReply: isReply, messageType: .Text, startsThread: startsThread)
    }
}

/// Records nothing.
struct NoAnalytics: AnalyticsServiceProtocol {
    let signpost = Signposter()
    func trackInteraction(index: Int?, name: AnalyticsEvent.Interaction.Name) { }
    func trackComposer(inThread: Bool, isEditing: Bool, isReply: Bool,
                       messageType: AnalyticsEvent.Composer.MessageType, startsThread: Bool?) { }
    func trackPinUnpinEvent(_ event: AnalyticsEvent.PinUnpinAction) { }
    func trackPollVote() { }
    func trackPollEnd() { }
    func trackRoomModeration(action: AnalyticsEvent.RoomModeration.Action, role: RoomRole?) { }
}

/// Element X measures how long a room takes to open. We do not.
struct Signposter {
    enum Transaction {
        case openRoom
        case notificationToMessage
    }

    enum SpanName {
        case timelineLoad
    }

    struct Span {
        func finish() { }
    }

    func finishTransaction(_ transaction: Transaction) { }

    func addSpan(_ name: SpanName, toTransaction transaction: Transaction) -> Span? { nil }
}
