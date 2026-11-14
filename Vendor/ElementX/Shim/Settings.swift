//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Stand-ins for Element X's AppSettings, AccountSettings and UserSettings, which live in its
// app target and carry every Labs flag. Only what the vendored chat views read is here, with
// the values our app wants: threads on, no calls, no location, no developer views.

import Combine
import Foundation

/// App-wide settings the chat views read.
final class AppSettings: @unchecked Sendable {
    // Threads from the first day (design README: "Threads under messages").
    let threadsEnabled = true
    var threadsEnabledPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    // Room list filters Element X offers behind flags; our channel list has none.
    let lowPriorityFilterEnabled = false
    let mentionsFilterEnabled = false

    let galleryEnabled = false
    let linkPreviewsEnabled = true
    let nativeCallEnabled = false
    let optimizeMediaUploads = true
    let reactionCelebrationsEnabled = false

    let viewSourceEnabled = false
    var viewSourceEnabledPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }

    let jumpToReadMarkerEnabled = true
    var jumpToReadMarkerEnabledPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    /// Voice messages from other clients play at this speed; the button under one cycles it.
    var voiceMessagePlaybackSpeed: AudioPlaybackSpeed {
        get { voiceMessagePlaybackSpeedSubject.value }
        set { voiceMessagePlaybackSpeedSubject.send(newValue) }
    }

    var voiceMessagePlaybackSpeedPublisher: AnyPublisher<AudioPlaybackSpeed, Never> {
        voiceMessagePlaybackSpeedSubject.eraseToAnyPublisher()
    }

    private let voiceMessagePlaybackSpeedSubject = CurrentValueSubject<AudioPlaybackSpeed, Never>(.default)

    /// Recently used emoji for the reaction picker, newest first, kept on this device.
    var frequentlyUsedSystemEmojis: [FrequentlyUsedEmoji] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.emojiKey),
                  let value = try? JSONDecoder().decode([FrequentlyUsedEmoji].self, from: data) else { return [] }
            return value
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.emojiKey)
        }
    }

    private static let emojiKey = "chatkit.frequentlyUsedSystemEmojis"

    // Help pages Element X links to from encryption notices. Our rooms are unencrypted, so these
    // notices never show; the addresses only keep the views compiling.
    let historySharingDetailsURL: URL = URL(string: "https://www.iphoneblog.de")!
    let identityPinningViolationDetailsURL: URL = URL(string: "https://www.iphoneblog.de")!
}

/// Per-account settings the chat views read.
final class AccountSettings: @unchecked Sendable {
    /// Read receipts and typing notices are shown and sent.
    /// No map provider: location sharing is off and received locations open Apple Maps.
    let mapTilerConfiguration = (publisher: CurrentValueSubject<MapTilerConfiguration, Never>(
        MapTilerConfiguration(baseURL: URL(string: "https://invalid.example")!, apiKey: nil, lightStyleID: "", darkStyleID: "")
    ), ())

    let sharePresence = true
    var sharePresencePublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }
}

/// The settings for a signed-in account, as Element X's views expect them.
final class UserSettings: @unchecked Sendable {
    let app: AppSettings
    let account: AccountSettings

    init(app: AppSettings = AppSettings(), account: AccountSettings = AccountSettings()) {
        self.app = app
        self.account = account
    }
}
