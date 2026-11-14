//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct TimelineItemMenu: View {
    @EnvironmentObject private var context: TimelineViewModel.Context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var reactionsFrame = CGRect.zero
    
    let item: EventBasedTimelineItemProtocol
    let actions: TimelineItemMenuActions
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        VStack(spacing: 8) {
            messagePreview
                .padding(.horizontal, 16)
                .padding(.top, 32.0)
                .padding(.bottom, 4.0)
                .frame(idealWidth: 300.0)
            
            Divider()
                .background(Color.compound.bgSubtlePrimary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0.0) {
                    if !actions.reactions.isEmpty {
                        reactionsSection
                            .padding(.bottom, 8.0)
                        
                        Divider()
                            .background(Color.compound.bgSubtlePrimary)
                    }
                    
                    if !actions.actions.isEmpty {
                        viewsForActions(actions.actions)
                        
                        Divider()
                            .background(Color.compound.bgSubtlePrimary)
                    }
                    
                    viewsForActions(actions.secondaryActions)
                }
            }
        }
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.timelineItemActionMenu)
        .presentationSizing(.page)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.compound.bgCanvasDefault)
        .presentationDragIndicator(.visible)
    }
    
    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 0.0) {
                LoadableAvatarImage(url: item.sender.avatarURL,
                                    name: item.sender.displayName,
                                    contentID: item.sender.id,
                                    avatarSize: .user(on: .timeline),
                                    mediaProvider: context.mediaProvider)
                    .accessibilityHidden(true)
                
                Spacer(minLength: 8.0)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.sender.displayName ?? item.sender.id)
                        .font(.compound.bodySMSemibold)
                        .foregroundColor(.compound.textPrimary)
                        .textSelection(.enabled)
                    
                    Text(item.timelineMenuDescription)
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 16.0)
                
                Text(item.timestamp.formattedTime())
                    .font(.compound.bodyXS)
                    .foregroundColor(.compound.textSecondary)
            }
            .accessibilityElement(children: .combine)
            
            if case let .sendingFailed(.verifiedUser(failure)) = item.properties.deliveryStatus {
                Divider()
                    .padding(.horizontal, -16)
                
                VerifiedUserSendFailureView(failure: failure,
                                            members: context.viewState.members,
                                            ownUserID: context.viewState.ownUserID) {
                    send(.itemSendInfoTapped(itemID: item.id))
                }
                .padding(.bottom, 8)
            } else if let authenticity = item.properties.encryptionAuthenticity {
                Label(authenticity.message, icon: authenticity.icon, iconSize: .small, relativeTo: .compound.bodySMSemibold)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(authenticity.foregroundStyle)
            }
        }
    }
    
    private var reactionsSection: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(actions.reactions, id: \.key) {
                        reactionButton(for: $0.key)
                    }
                }
                .padding(.horizontal)
                .frame(minWidth: reactionsFrame.width, maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .readFrame($reactionsFrame)
            .overlay {
                if horizontalSizeClass == .compact {
                    LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                           .init(color: .clear, location: 0.9),
                                           .init(color: .compound.bgCanvasDefault, location: 1.0)],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                        .allowsHitTesting(false)
                }
            }
            
            Button {
                dismiss()
                // Otherwise we get errors that a sheet is already presented
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    context.send(viewAction: .displayEmojiPicker(itemID: item.id))
                }
            } label: {
                CompoundIcon(\.reactionAdd, size: .medium, relativeTo: .compound.headingLG)
                    .foregroundColor(.compound.iconSecondary)
                    .padding(10)
            }
            .accessibilityLabel(L10n.actionReact)
        }
    }
    
    private func reactionButton(for emoji: String) -> some View {
        Button {
            feedbackGenerator.impactOccurred()
            dismiss()
            context.send(viewAction: .toggleReaction(key: emoji, itemID: item.id))
        } label: {
            Text(emoji)
                .font(.compound.headingLG)
                .padding(8)
                .background(Circle()
                    .foregroundColor(reactionBackgroundColor(for: emoji)))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(hasReacted(to: emoji) ? L10n.a11yRemoveReaction(emoji) : L10n.a11yAddReaction(emoji))
    }
    
    private func hasReacted(to emoji: String) -> Bool {
        if let reaction = item.properties.reactions.first(where: { $0.key == emoji }),
           reaction.isHighlighted {
            return true
        }
        return false
    }
    
    private func reactionBackgroundColor(for emoji: String) -> Color {
        hasReacted(to: emoji) ? .compound.bgActionPrimaryRest : .clear
    }
    
    private func viewsForActions(_ actions: [TimelineItemMenuAction]) -> some View {
        ForEach(actions, id: \.self) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                send(action)
            } label: {
                action.label
            }
            .buttonStyle(.menuSheet)
        }
    }
    
    private func send(_ action: TimelineItemMenuAction) {
        send(.handleTimelineItemMenuAction(itemID: item.id, action: action))
    }
    
    private func send(_ action: TimelineViewAction) {
        dismiss()
        // Otherwise we might get errors that a sheet is already presented
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            context.send(viewAction: action)
        }
    }
}

private struct VerifiedUserSendFailureView: View {
    let failure: TimelineItemSendFailure.VerifiedUser
    let action: () -> Void
    
    private let memberDisplayName: String
    private let isYou: Bool
    
    init(failure: TimelineItemSendFailure.VerifiedUser,
         members: [String: RoomMemberState],
         ownUserID: String,
         action: @escaping () -> Void) {
        self.failure = failure
        self.action = action
        
        let userIDs = failure.affectedUserIDs
        memberDisplayName = userIDs.first.map { members[$0]?.displayName ?? $0 } ?? ""
        isYou = ownUserID == userIDs.first
    }
    
    var title: String {
        switch failure {
        case .hasUnsignedDevice:
            isYou ? L10n.screenTimelineItemMenuSendFailureYouUnsignedDevice : L10n.screenTimelineItemMenuSendFailureUnsignedDevice(memberDisplayName)
        case .changedIdentity:
            L10n.screenTimelineItemMenuSendFailureChangedIdentity(memberDisplayName)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, icon: \.errorSolid, iconSize: .small, relativeTo: .compound.bodySMSemibold)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textCriticalPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ListRowAccessory.navigationLink
            }
        }
    }
}

private extension EncryptionAuthenticity {
    var foregroundStyle: SwiftUI.Color {
        switch color {
        case .red: .compound.textCriticalPrimary
        case .gray: .compound.textSecondary
        }
    }
}

// MARK: - Previews
