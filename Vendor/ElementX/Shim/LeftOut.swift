//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Small replacements for Element X parts we left out (Vendor/ElementX/UPSTREAM.md, "Shim before
// patch"). Each keeps the upstream name, so the vendored code that refers to it compiles unchanged.

import Compound
import SwiftUI

// MARK: - Location (Element X draws a MapLibre map; we show a line that opens Apple Maps)

/// A shared location from another client: a pin and the sender's text, tap opens Maps.
struct LocationRoomTimelineView: View {
    let timelineItem: LocationRoomTimelineItem

    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            LeftOutLocationLabel(text: timelineItem.content.body, geoURI: timelineItem.content.geoURI)
        }
    }
}

/// A live location from another client. We do not follow it; we show where it was last.
struct LiveLocationRoomTimelineView: View {
    let timelineItem: LiveLocationRoomTimelineItem
    let isStopped: Bool

    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            LeftOutLocationLabel(text: timelineItem.body, geoURI: timelineItem.content.lastGeoURI)
        }
    }
}

private struct LeftOutLocationLabel: View {
    let text: String
    let geoURI: GeoURI?

    var body: some View {
        if let geoURI, let url = URL(string: "https://maps.apple.com/?ll=\(geoURI.latitude),\(geoURI.longitude)") {
            Link(destination: url) { label }
        } else {
            label
        }
    }

    private var label: some View {
        Label(text, icon: \.locationPin, iconSize: .small, relativeTo: .compound.bodyLG)
            .labelStyle(RoomTimelineViewPlaceholderLabelStyle())
    }
}

// MARK: - Calls and live location sharing

/// Element Call is not part of our app. The room proxy's protocol still names the driver.
protocol ElementCallWidgetDriverProtocol { }

/// Live location sharing is not part of our app. The room proxy's protocol still names it.
protocol RoomLiveLocationServiceProtocol { }

/// Element X's service that shares the user's own live location. We never share; stopping is a no-op.
protocol LiveLocationServiceProtocol {
    func stopLiveLocation(roomID: String) async
}

struct NoLiveLocationService: LiveLocationServiceProtocol {
    func stopLiveLocation(roomID: String) async { }
}

/// A live location share, as the thread screen's navigation names it. Never created by us.
struct LiveLocationShare: Hashable, Identifiable {
    let userID: String
    let geoURI: GeoURI?
    let timestamp: Date
    let timeoutDate: Date

    var id: String { userID }
}

// MARK: - Test support

/// Element X's UI tests pick a screen by this identifier. We have none.
enum UITestsScreenIdentifier: String {
    case none
}

// MARK: - Navigation

/// Where a room timeline should open, as Element X's room flow names it.
struct FocusEvent: Hashable {
    /// The event ID that the timeline should be focussed around.
    let eventID: String
    /// Whether the focus comes from the pinned timeline (never in our app).
    let shouldSetPin: Bool
}

// MARK: - Composer

/// The composer's size limits, defined in Element X's room screen coordinator (not vendored).
enum ComposerConstant {
    static let minHeight: CGFloat = 22
    static let maxHeight: CGFloat = 250
    static let allowedHeightRange = minHeight...maxHeight
    static let translationThreshold: CGFloat = 60
}
