//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct TimelineThreadSummaryView: View {
    let threadSummary: TimelineItemThreadSummary
    var onTap: (() -> Void)?
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            content
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch threadSummary {
        case .loaded(let senderID, let sender, let latestEventContent, let numberOfReplies):
            switch latestEventContent {
            case .message(let content):
                switch content {
                case .audio(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.caption ?? content.filename,
                               formattedBody: content.formattedCaption,
                               numberOfReplies: numberOfReplies)
                case .emote(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.body,
                               formattedBody: content.formattedBody,
                               numberOfReplies: numberOfReplies)
                case .file(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.caption ?? content.filename,
                               formattedBody: content.formattedCaption,
                               numberOfReplies: numberOfReplies)
                case .image(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.caption ?? content.filename,
                               formattedBody: content.formattedCaption,
                               numberOfReplies: numberOfReplies)
                case .notice(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.body,
                               formattedBody: content.formattedBody,
                               numberOfReplies: numberOfReplies)
                case .text(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.body,
                               formattedBody: content.formattedBody,
                               numberOfReplies: numberOfReplies)
                case .video(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.caption ?? content.filename,
                               formattedBody: content.formattedCaption,
                               numberOfReplies: numberOfReplies)
                case .voice:
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: L10n.commonVoiceMessage,
                               formattedBody: nil,
                               numberOfReplies: numberOfReplies)
                case .location:
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: L10n.commonSharedLocation,
                               formattedBody: nil,
                               numberOfReplies: numberOfReplies)
                case .gallery(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.caption ?? content.body,
                               formattedBody: content.formattedCaption,
                               numberOfReplies: numberOfReplies)
                }
            case .poll(let question):
                ThreadView(senderID: senderID,
                           sender: sender,
                           plainBody: question,
                           formattedBody: nil,
                           numberOfReplies: numberOfReplies)
            case .liveLocation:
                ThreadView(senderID: senderID,
                           sender: sender,
                           plainBody: L10n.commonSharedLiveLocation,
                           formattedBody: nil,
                           numberOfReplies: numberOfReplies)
            case .redacted:
                ThreadView(senderID: senderID,
                           sender: sender,
                           plainBody: L10n.commonMessageRemoved,
                           formattedBody: nil,
                           numberOfReplies: numberOfReplies)
            }
        default:
            LoadingThreadView()
        }
    }
    
    private struct LoadingThreadView: View {
        var body: some View {
            ThreadView(senderID: "@alice:matrix.org",
                       sender: nil,
                       plainBody: "Hello world",
                       formattedBody: nil,
                       numberOfReplies: 42)
                .redacted(reason: .placeholder)
                .accessibilityLabel(L10n.commonLoading)
        }
    }
    
    private struct ThreadView: View {
        @EnvironmentObject private var context: TimelineViewModel.Context
        
        let senderID: String
        let sender: TimelineItemSender?
        let plainBody: String
        let formattedBody: AttributedString?
        let numberOfReplies: Int
        
        var body: some View {
            HStack(spacing: 4) {
                CompoundIcon(\.threads, size: .xSmall, relativeTo: .compound.bodyXS)
                    .foregroundColor(.compound.iconSecondary)
                    .accessibilityLabel(L10n.commonThread)
                
                Text(L10n.commonReplies(numberOfReplies))
                    .font(.compound.bodyXSSemibold)
                    .foregroundColor(.compound.textPrimary)
                
                LoadableAvatarImage(url: sender?.avatarURL,
                                    name: sender?.displayName,
                                    contentID: senderID,
                                    avatarSize: .user(on: .threadSummary),
                                    mediaProvider: context.mediaProvider)
                    .accessibilityHidden(true)
                
                Text(sender?.disambiguatedDisplayName ?? senderID)
                    .font(.compound.bodyXSSemibold)
                    .foregroundColor(.compound.textPrimary)
                    .accessibilityLabel(L10n.commonInReplyTo(sender?.disambiguatedDisplayName ?? senderID))
                
                Text(context.viewState.buildMessagePreview(formattedBody: formattedBody, plainBody: plainBody))
                    .font(.compound.bodyXS)
                    .foregroundColor(.compound.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .lineLimit(1)
            .padding(.vertical, 7.0)
            .padding(.horizontal, 8.0)
            .background(Color.compound.bgSubtlePrimary)
            .cornerRadius(8)
        }
    }
}
