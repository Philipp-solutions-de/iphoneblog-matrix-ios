//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// How far a photo, video or file is on its way up. The SDK reports it in each local echo's send
// state (ChatSession turns the report on); Element X reads only "sending". One line in
// TimelineItemProxy.swift (patch) hands the fraction here, and the message row draws it as a bar.

import Combine
import Foundation
import MatrixRustSDK

@MainActor
final class ChatUploadProgress: ObservableObject {
    static let shared = ChatUploadProgress()

    /// Fraction done, 0...1, by the timeline item's unique ID; absent once sent or failed.
    @Published private(set) var fractions: [TimelineItemIdentifier.UniqueID: Double] = [:]

    func fraction(for id: TimelineItemIdentifier) -> Double? { fractions[id.uniqueID] }

    /// Called while timeline items are built, on any thread.
    nonisolated static func report(_ id: TimelineItemIdentifier, state: EventSendState?) {
        let fraction: Double?
        if case .notSentYet(let progress?) = state, progress.progress.total > 0 {
            fraction = min(1, Double(progress.progress.current) / Double(progress.progress.total))
        } else {
            fraction = nil
        }
        let uniqueID = id.uniqueID
        Task { @MainActor in
            let store = ChatUploadProgress.shared
            guard store.fractions[uniqueID] != fraction else { return }
            store.fractions[uniqueID] = fraction
        }
    }
}
