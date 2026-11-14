//
// iphoneblog: the hooks that turn Element X into the iphoneblog app.
//
// SPDX-License-Identifier: AGPL-3.0-only
//
// Element X registers replacement hooks in `AppHooks.setUp()`. This file provides that
// method for the main app only, so upstream code stays untouched. The values come from
// `IphoneblogBrand`, which scripts/prepare.sh writes from brand.env.
//

#if IS_MAIN_APP

import Compound
import SwiftUI
import UIKit

extension AppHooks {
    func setUp() {
        registerAppSettingsHook(IphoneblogAppSettingsHook())
        registerCompoundHook(IphoneblogCompoundHook())
        registerUserSessionHook(IphoneblogUserSessionHook())
    }
}

// MARK: - Settings

struct IphoneblogAppSettingsHook: AppSettingsHookProtocol {
    /// Bumped when the defaults below change and must reach installed apps once more.
    private static let defaultsVersionKey = "iphoneblog.defaultsVersion"
    private static let defaultsVersion = 1

    func configure(_ appSettings: AppSettings) -> AppSettings {
        let base = IphoneblogBrand.websiteURL
        let bundleID = InfoPlistReader.main.bundleIdentifier

        appSettings.override(accountProviders: [.managed(serverName: IphoneblogBrand.matrixServerName,
                                                          baseURL: IphoneblogBrand.matrixBaseURL)],
                             allowOtherAccountProviders: false,
                             hideBrandChrome: false,
                             pushGatewayBaseURL: IphoneblogBrand.pushGatewayBaseURL,
                             oAuthRedirectURL: base.appending(path: "oauth/ios/\(bundleID)"),
                             oAuthClientURIPath: "apps/ios",
                             websiteURL: base,
                             logoURL: IphoneblogBrand.logoURL,
                             copyrightURL: IphoneblogBrand.copyrightURL,
                             acceptableUseURL: IphoneblogBrand.termsURL,
                             privacyURL: IphoneblogBrand.privacyURL,
                             encryptionURL: appSettings.encryptionURL,
                             deviceVerificationURL: appSettings.deviceVerificationURL,
                             chatBackupDetailsURL: appSettings.chatBackupDetailsURL,
                             identityPinningViolationDetailsURL: appSettings.identityPinningViolationDetailsURL,
                             historySharingDetailsURL: appSettings.historySharingDetailsURL,
                             elementWebHosts: [],
                             accountProvisioningHost: IphoneblogBrand.matrixServerName,
                             bugReportApplicationID: "iphoneblog-ios",
                             analyticsTermsURL: nil,
                             bundledMapTilerConfiguration: appSettings.bundledMapTilerConfiguration)

        // Threads and "link a new device" by QR code are on for every new install.
        // Applied once per version, so a person who turns them off keeps them off.
        let store = UserDefaults(suiteName: AppSettings.suiteName) ?? .standard
        if store.integer(forKey: Self.defaultsVersionKey) < Self.defaultsVersion {
            appSettings.threadsEnabled = true
            appSettings.linkNewDeviceEnabled = true
            store.set(Self.defaultsVersion, forKey: Self.defaultsVersionKey)
        }

        return appSettings
    }
}

// MARK: - Colours

struct IphoneblogCompoundHook: CompoundHookProtocol {
    func override(colors: CompoundColors, uiColors: CompoundUIColors) {
        // Buttons: the blog's teal, dark enough for white text in light mode,
        // light enough for black text in dark mode.
        let action = UIColor.iphoneblog(light: IphoneblogBrand.brandColorDarkText, dark: IphoneblogBrand.brandColorLightOnDark)
        let actionPressed = UIColor.iphoneblog(light: IphoneblogBrand.brandColorPressed, dark: IphoneblogBrand.brandColor)
        // Text, icons and links that carry the accent.
        let accent = UIColor.iphoneblog(light: IphoneblogBrand.brandColorDarkText, dark: IphoneblogBrand.brandColorLightOnDark)

        let pairs: [(KeyPath<CompoundColorTokens, Color> & Sendable, KeyPath<CompoundUIColorTokens, UIColor> & Sendable, UIColor)] = [
            (\.bgActionPrimaryRest, \.bgActionPrimaryRest, action),
            (\.bgActionPrimaryHovered, \.bgActionPrimaryHovered, actionPressed),
            (\.bgActionPrimaryPressed, \.bgActionPrimaryPressed, actionPressed),
            (\.bgAccentRest, \.bgAccentRest, action),
            (\.bgAccentHovered, \.bgAccentHovered, actionPressed),
            (\.bgAccentPressed, \.bgAccentPressed, actionPressed),
            (\.textActionAccent, \.textActionAccent, accent),
            (\.textLinkExternal, \.textLinkExternal, accent),
            (\.iconAccentPrimary, \.iconAccentPrimary, accent),
            (\.iconAccentTertiary, \.iconAccentTertiary, accent)
        ]

        for (colorPath, uiColorPath, color) in pairs {
            colors.override(colorPath, with: Color(uiColor: color))
            uiColors.override(uiColorPath, with: color)
        }
    }
}

private extension UIColor {
    static func iphoneblog(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Calls hidden

/// Hides every call button. The trial has no call server, so a call would fail.
struct IphoneblogUserSessionHook: UserSessionHookProtocol {
    func makeUserHooks(for clientProxy: ClientProxyProtocol) -> UserHooks {
        UserHooks(roomScreenHook: IphoneblogRoomScreenHook(),
                  roomDetailsScreenHook: IphoneblogRoomDetailsScreenHook(),
                  roomMemberDetailsScreenHook: IphoneblogRoomMemberDetailsScreenHook(),
                  userProfileScreenHook: IphoneblogUserProfileScreenHook())
    }

    func configure(_ userSettings: UserSettings, forHomeserver homeserver: String) -> UserSettings {
        userSettings
    }
}

struct IphoneblogRoomScreenHook: RoomScreenHookProtocol {
    func update(_ viewState: RoomScreenViewState) -> RoomScreenViewState {
        var viewState = viewState
        viewState.isCallingEnabled = false
        return viewState
    }
}

struct IphoneblogRoomDetailsScreenHook: RoomDetailsScreenHookProtocol {
    func update(_ viewState: RoomDetailsScreenViewState) -> RoomDetailsScreenViewState {
        var viewState = viewState
        viewState.isCallingEnabled = false
        return viewState
    }
}

struct IphoneblogRoomMemberDetailsScreenHook: RoomMemberDetailsScreenHookProtocol {
    func update(_ viewState: RoomMemberDetailsScreenViewState) -> RoomMemberDetailsScreenViewState {
        var viewState = viewState
        viewState.isCallingEnabled = false
        return viewState
    }

    func update(_ createRoomParameters: CreateRoomParameters) -> CreateRoomParameters {
        createRoomParameters
    }
}

struct IphoneblogUserProfileScreenHook: UserProfileScreenHookProtocol {
    func update(_ viewState: UserProfileScreenViewState) -> UserProfileScreenViewState {
        var viewState = viewState
        viewState.isCallingEnabled = false
        return viewState
    }

    func update(_ createRoomParameters: CreateRoomParameters) -> CreateRoomParameters {
        createRoomParameters
    }
}

#endif
