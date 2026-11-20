//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Our message row, Slack's structure in Quill's calm (design proposal, screens 03 to 05):
// the sender's avatar and name once per group, the time beside the name, the message below
// without a bubble, reactions and "n Antworten" under it. Element X's TimelineStyler draws
// every message through this view instead of its bubbles (one patch in TimelineStyler.swift).
// The gestures, menus and accessibility are Element X's own modifiers, unchanged.

import Compound
import SwiftUI

struct TimelineItemRowStylerView<Content: View>: View {
    @EnvironmentObject private var context: TimelineViewModel.Context
    @Environment(\.timelineGroupStyle) private var timelineGroupStyle
    @Environment(\.focussedEventID) private var focussedEventID
    @ObservedObject private var uploads = ChatUploadProgress.shared
    @Environment(\.openURL) private var parentOpenURL
    /// When a link or mention in this message was last tapped: that tap is not a thread tap.
    @State private var linkTappedAt: Date?

    let timelineItem: EventBasedTimelineItemProtocol
    let adjustedDeliveryStatus: TimelineItemDeliveryStatus?
    @ViewBuilder let content: () -> Content

    private var style: ChatKitStyle { ChatKitStyle.current }

    /// The first reply under a thread's root always names its sender, even when the root's
    /// writer answers; otherwise it reads like a caption of the line above.
    private var showsSender: Bool { timelineGroupStyle.shouldShowSenderDetails || isFirstThreadReply }

    private var threadRootID: String? {
        if case .thread(let rootEventID) = context.viewState.timelineKind { return rootEventID }
        return nil
    }

    /// The thread's messages after the root, as the timeline holds them now (sent and sending).
    private var threadReplies: [TimelineItemIdentifier.UniqueID] {
        guard let threadRootID else { return [] }
        return context.viewState.timelineState.itemViewStates.compactMap { item in
            guard case .event = item.identifier, item.identifier.eventID != threadRootID else { return nil }
            if case .state = item.type { return nil }
            return item.id
        }
    }

    private var isFirstThreadReply: Bool {
        threadRootID != nil && threadReplies.first == timelineItem.id.uniqueID
    }

    private var isFocussed: Bool {
        focussedEventID != nil && timelineItem.id.eventID == focussedEventID
    }

    /// In a thread, the first message heads the screen and the replies follow under a line.
    private var isThreadRoot: Bool {
        if case .thread(let rootEventID) = context.viewState.timelineKind {
            return timelineItem.id.eventID == rootEventID
        }
        return false
    }

    private var isMessageSelectionActive: Bool { context.viewState.messageSelection.isActive }

    /// Pictures and videos get rounded corners and a size limit; text uses the full width.
    private var isMedia: Bool {
        timelineItem is ImageRoomTimelineItem || timelineItem is VideoRoomTimelineItem || timelineItem is StickerRoomTimelineItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: style.metrics.avatarGap) {
                avatarColumn
                VStack(alignment: .leading, spacing: 4) {
                    if showsSender { header }
                    messageWithActions
                    supplements
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, style.metrics.page)
            .padding(.top, showsSender ? style.metrics.groupSpacing : style.metrics.messageSpacing)
            .padding(.bottom, 2)
            // A message shown on request (a search hit) fades in and out once; a restored read
            // position not at all. Element X's lasting green band read as a status (Thorsten).
            .modifier(ChatFocusFlash(isOn: isFocussed && !(focussedEventID.map(ChatReadPositions.shared.isQuiet) ?? false)))

            if isThreadRoot { threadRootFooter }
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var avatarColumn: some View {
        if showsSender {
            // A fixed frame: Element X scales its pictures with Dynamic Type, while the empty
            // column under a follow-up message does not, so the text wobbled (Philip, 2026-11-18).
            ChatAvatar(sender: timelineItem.sender, size: style.metrics.avatar, mediaProvider: context.mediaProvider)
                .frame(width: style.metrics.avatar, height: style.metrics.avatar)
                .onTapGesture { context.send(viewAction: .tappedOnSenderDetails(sender: timelineItem.sender)) }
                .highPriorityGesture(shareContactGesture)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: style.metrics.avatar, height: 1)
        }
    }

    /// A long press on a name or avatar: "Kontaktdaten teilen" with that person (ChatKitContacts);
    /// the rest of the row keeps the message's own long press.
    private var shareContactGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            ChatKitContacts.share?(timelineItem.sender.id)
        }
    }

    /// Listed by the chat server as a bot (ChatKitBots), never guessed from the name.
    private var isBot: Bool { ChatKitBots.isBot(timelineItem.sender.id) }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                .font(style.fonts.senderName)
                .foregroundStyle(isBot ? style.colors.accent : style.colors.ink)
                .lineLimit(1)
                .accessibilityHidden(true) // read by the accessibility modifier below
                #if DEBUG
                // For UI tests (ThreadHeaderUITests): where the name starts, to line the text up with it.
                .overlay {
                    Color.clear.accessibilityElement().accessibilityIdentifier("row.senderName")
                }
                #endif
                .onTapGesture { context.send(viewAction: .tappedOnSenderDetails(sender: timelineItem.sender)) }
                .highPriorityGesture(shareContactGesture)
            if isBot { ChatBotPill().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 } }
            Text(ChatTimeLabel.short(timelineItem.timestamp))
                .font(style.fonts.time)
                .foregroundStyle(style.colors.ink3)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            // A visible way to react (testers: reactions were "mega versteckt" behind the long
            // press, which stays); next to existing reactions Element X has its own + button.
            if timelineItem.canBeRepliedTo, !isMessageSelectionActive {
                Button { context.send(viewAction: .displayEmojiPicker(itemID: timelineItem.id)) } label: {
                    CompoundIcon(\.reactionAdd, size: .xSmall, relativeTo: .compound.bodySM)
                        .foregroundStyle(style.colors.ink3.opacity(0.7))
                        .frame(width: 32, height: 24, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.actionReact)
                .accessibilityIdentifier("row-react")
            }
        }
    }

    private var messageWithActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyDetails = timelineItem.properties.replyDetails {
                TimelineReplyView(placement: .timeline, timelineItemReplyDetails: replyDetails)
                    .onTapGesture { context.send(viewAction: .focusOnEventID(replyDetails.eventID)) }
            }
            if isMedia {
                content()
                    .frame(maxWidth: style.metrics.mediaWidth, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: style.metrics.corner, style: .continuous))
            } else {
                content()
            }
            // A photo, video or file on its way up: how far it is, from the SDK's send state.
            if let fraction = uploads.fraction(for: timelineItem.id) {
                ProgressView(value: fraction)
                    .tint(style.colors.accent)
                    .frame(maxWidth: style.metrics.mediaWidth)
                    .accessibilityLabel(ChatKitStrings.uploading)
                    .accessibilityValue("\(Int(fraction * 100)) %")
            }
        }
        .contentShape(Rectangle())
        .timelineItemAccessibility(timelineItem) {
            context.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id))
        }
        .onTapGesture { } // keeps the long press working, as in Element X's bubble view
        // A tap on a message opens its thread, as in Slack, also to start one; inside a thread it
        // does nothing. The text is a UITextView that keeps taps to itself, so the gesture runs
        // alongside it; a link or mention it opened (through openURL, recorded here) wins.
        // Pictures and videos keep their own tap (the preview).
        .environment(\.openURL, OpenURLAction { url in
            linkTappedAt = .now
            parentOpenURL(url)
            return .handled
        })
        .simultaneousGesture(TapGesture().onEnded { openThreadUnlessLink() }, including: isMedia ? .subviews : .all)
        .longPressWithFeedback(isEnabled: !isMessageSelectionActive) {
            context.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id))
        }
        // Right: answer in the thread; left: the message's menu with its reaction bar (Alex's
        // request). Inside a thread the right swipe does nothing at all, no icon either (Philip,
        // 2026-11-18). MessageSwipe keeps the screen's left edge free for swipe-back.
        .messageSwipe(isEnabled: { !isMessageSelectionActive && timelineItem.canBeRepliedTo },
                      allowsRight: { !context.viewState.timelineKind.isThread }) {
            CompoundIcon(\.threads)
                .foregroundColor(style.colors.accent)
                .accessibilityHidden(true)
        } trailing: {
            CompoundIcon(\.reactionAdd)
                .foregroundColor(style.colors.ink2)
                .accessibilityHidden(true)
        } swipedRight: {
            guard !context.viewState.timelineKind.isThread else { return }
            context.send(viewAction: .displayThread(itemID: timelineItem.id))
        } swipedLeft: {
            context.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id))
        }
    }

    private func openThreadUnlessLink() {
        guard !context.viewState.timelineKind.isThread, !isMessageSelectionActive,
              timelineItem.canBeRepliedTo else { return }
        // The text view reports a link on touch-up too; give it a moment to do so.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let linkTappedAt, Date.now.timeIntervalSince(linkTappedAt) < 0.6 { return }
            context.send(viewAction: .displayThread(itemID: timelineItem.id))
        }
    }

    @ViewBuilder
    private var supplements: some View {
        if !timelineItem.properties.reactions.isEmpty {
            TimelineReactionsView(context: context,
                                  itemID: timelineItem.id,
                                  reactions: timelineItem.properties.reactions,
                                  isLayoutRTL: false)
                .onTapGesture { } // stops the message's long press from taking the reaction's touch
        }

        if context.viewState.areThreadsEnabled,
           !context.viewState.timelineKind.isThread,
           let summary = timelineItem.properties.threadSummary,
           case let .loaded(_, sender, latestEventContent, numberOfReplies) = summary {
            ChatThreadSummary(roomID: context.viewState.roomID,
                              rootEventID: timelineItem.id.eventID ?? "",
                              latestSender: sender,
                              preview: latestEventContent.plainPreview,
                              numberOfReplies: numberOfReplies,
                              mediaProvider: context.mediaProvider) {
                context.send(viewAction: .displayThread(itemID: timelineItem.id))
            }
        }

        // Sending, failed and read receipts on your last message, as Element X shows them.
        if timelineItem.isOutgoing {
            TimelineItemStatusView(timelineItem: timelineItem, adjustedDeliveryStatus: adjustedDeliveryStatus)
                .environmentObject(context)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var threadRootFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(style.colors.line).frame(height: 1).padding(.top, 12)
            ThreadRootCount(roomID: context.viewState.roomID, rootEventID: threadRootID ?? "",
                            loaded: threadReplies.count)
                .font(style.fonts.dayDivider)
                .foregroundStyle(style.colors.ink3)
                .padding(.horizontal, style.metrics.page)
                .padding(.top, 14)
        }
    }
}

// MARK: - Avatar

/// A person's picture, or their initials on a colour that stays the same for them.
struct ChatAvatar: View {
    let sender: TimelineItemSender
    let size: CGFloat
    let mediaProvider: MediaProviderProtocol?

    private var style: ChatKitStyle { ChatKitStyle.current }

    /// A squircle, as every person's picture in the app (ChatKitStyle.Metrics.avatarCornerFraction).
    static func shape(_ size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size * ChatKitStyle.current.metrics.avatarCornerFraction, style: .continuous)
    }

    var body: some View {
        if sender.avatarURL != nil {
            LoadableAvatarImage(url: sender.avatarURL, name: sender.displayName, contentID: sender.id,
                                shape: .squircle, avatarSize: .custom(size), mediaProvider: mediaProvider)
        } else {
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Self.shape(size).fill(color))
        }
    }

    private var initials: String {
        let name = sender.displayName ?? String(sender.id.dropFirst().prefix(while: { $0 != ":" }))
        let words = name.split(separator: " ").prefix(2)
        let letters = words.count > 1 ? words.compactMap(\.first) : Array(name.prefix(1))
        return String(letters).uppercased()
    }

    /// The same colour for the same person on every device: a stable hash of the user ID.
    private var color: Color {
        let colors = style.colors.avatars
        guard !colors.isEmpty else { return style.colors.accent }
        let sum = sender.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return colors[sum % colors.count]
    }
}

// MARK: - Thread root count

/// "90 Antworten" under a thread's first message: the server's count, since the thread timeline
/// loads replies page by page (it said 20 for a thread of 90 in the perf tests); the loaded
/// count until the server has answered. Its own view, so only it follows ChatThreadActivity.
struct ThreadRootCount: View {
    let roomID: String
    let rootEventID: String
    let loaded: Int
    @ObservedObject private var activity = ChatThreadActivity.shared
    private var style: ChatKitStyle { ChatKitStyle.current }

    var body: some View {
        Text(ChatKitStrings.replies(max(loaded, activity.thread(roomID: roomID, rootEventID: rootEventID)?.serverReplies ?? 0)))
            .onAppear { activity.loadRepliers(roomID: roomID, rootEventID: rootEventID, hint: -1) }
    }
}

// MARK: - Thread summary

/// The thread row under a message (Slack's pattern, our colours): up to three repliers, the
/// count in teal, when the last reply came in grey. Unread replies make it bold with a dot.
struct ChatThreadSummary: View {
    let roomID: String
    let rootEventID: String
    let latestSender: TimelineItemSender
    let preview: String
    let numberOfReplies: Int
    let mediaProvider: MediaProviderProtocol?
    let action: () -> Void

    @ObservedObject private var activity = ChatThreadActivity.shared
    private var style: ChatKitStyle { ChatKitStyle.current }

    private var thread: ChatThreadActivity.Thread? { activity.thread(roomID: roomID, rootEventID: rootEventID) }
    /// The server's count once fetched; the timeline's summary and the thread list can be off.
    private var count: Int { ChatThreadCount.replies(server: thread?.serverReplies, timeline: numberOfReplies, repliers: thread?.repliers.count ?? 0) }
    private var isUnread: Bool { activity.isUnread(roomID: roomID, rootEventID: rootEventID) }
    private var repliers: [TimelineItemSender] {
        let known = thread?.repliers ?? []
        return Array((known.isEmpty ? [latestSender] : known).prefix(3))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(repliers, id: \.id) { sender in
                        ChatAvatar(sender: sender, size: style.metrics.summaryAvatar, mediaProvider: mediaProvider)
                            .overlay(ChatAvatar.shape(style.metrics.summaryAvatar).stroke(style.colors.background, lineWidth: 1.5))
                    }
                }
                Text(ChatKitStrings.replies(count))
                    .font(style.fonts.threadSummary.weight(isUnread ? .bold : .semibold))
                    .foregroundStyle(style.colors.accent)
                if let last = thread?.lastReply {
                    Text(ChatKitStrings.lastReply(last))
                        .font(style.fonts.threadPreview.weight(isUnread ? .semibold : .regular))
                        .foregroundStyle(style.colors.ink3)
                        .lineLimit(1)
                }
                if isUnread {
                    Circle().fill(style.colors.accent).frame(width: 7, height: 7)
                        .accessibilityLabel(ChatKitStrings.unread)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("thread-row")
        .onAppear { activity.loadRepliers(roomID: roomID, rootEventID: rootEventID, hint: numberOfReplies) }
        .onChange(of: numberOfReplies) { activity.loadRepliers(roomID: roomID, rootEventID: rootEventID, hint: numberOfReplies) }
    }
}

private extension TimelineEventContent {
    /// One line of the last reply, for the thread summary.
    var plainPreview: String {
        switch self {
        case .message(let content):
            switch content {
            case .text(let content): content.body
            case .emote(let content): content.body
            case .notice(let content): content.body
            case .image(let content): content.caption ?? L10n.commonImage
            case .video(let content): content.caption ?? L10n.commonVideo
            case .file(let content): content.caption ?? content.filename
            case .audio(let content): content.caption ?? content.filename
            default: ""
            }
        default:
            ""
        }
    }
}

/// "14:02" for a message row, formatted once per time: SwiftUI re-renders rows on every view
/// state change, and Date.formatted builds a formatter each time (perf review, 2026-11-16).
@MainActor
enum ChatTimeLabel {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    private static var cache: [TimeInterval: String] = [:]

    static func short(_ date: Date) -> String {
        let key = date.timeIntervalSinceReferenceDate.rounded(.down)
        if let known = cache[key] { return known }
        if cache.count > 2_000 { cache.removeAll(keepingCapacity: true) }
        let label = formatter.string(from: date)
        cache[key] = label
        return label
    }
}

/// A brief tint on a message the reader was sent to, gone after a second and a half.
struct ChatFocusFlash: ViewModifier {
    let isOn: Bool
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .background(Color.compound.gradientSubtleStop1.opacity(visible ? 1 : 0))
            .onAppear { if isOn { flash() } }
            .onChange(of: isOn) { _, on in if on { flash() } }
    }

    private func flash() {
        visible = true
        withAnimation(.easeOut(duration: 1.5).delay(0.3)) { visible = false }
    }
}
