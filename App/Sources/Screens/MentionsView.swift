import SwiftUI

/// @Mentions (preview 4): who mentioned me where, newest first; unread rows tinted teal with a teal
/// dot. A tap opens the place: the channel, its thread, or the article's discussion.
struct MentionsView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var mentions: MentionsModel
    @ObservedObject var router: Router

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle("@Mentions")
            if mentions.items.isEmpty {
                if mentions.hasLoaded {
                    ContentUnavailableView("Noch keine @Mentions", systemImage: "at",
                                           description: Text("Wenn dich jemand erwähnt, steht es hier."))
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(mentions.items) { mention in
                            Button { open(mention) } label: {
                                MentionRow(mention: mention, me: myNames)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .refreshable { mentions.reload() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .onAppear { mentions.reload() }
    }

    /// The words that mark me in a message: "@Tim", "Tim B.", "tim".
    private var myNames: [String] {
        [session.displayName, MentionsModel.localpart(session.userID)].compactMap { $0 }.filter { !$0.isEmpty }
    }

    private func open(_ mention: MentionsModel.Mention) {
        switch mention.place {
        case .channel(let roomID, let root?):
            router.openThread(roomID: roomID, rootEventID: root)
        case .channel(let roomID, nil):
            router.openRoom(roomID)
        case .discussion(let root, _):
            router.tab = .blog
            router.blogPath = [.thread(rootEventID: root)]
        case .room(let roomID, _):
            router.openRoom(roomID)
        }
    }
}

struct MentionRow: View {
    let mention: MentionsModel.Mention
    let me: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InitialsAvatar(name: mention.senderName, size: Theme.Size.chatAvatar, corner: Theme.Size.chatAvatarCorner)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(context.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(context.color)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Theme.ink3).accessibilityHidden(true)
                    Text(MentionRow.shortTime(mention.date))
                        .font(Theme.Font.time)
                        .foregroundStyle(Theme.ink3)
                    Spacer(minLength: 4)
                    if mention.unread {
                        Circle().fill(Theme.teal)
                            .frame(width: Theme.Size.unreadDot, height: Theme.Size.unreadDot)
                            .accessibilityLabel("ungelesen")
                    }
                }
                Text(mention.senderName)
                    .font(Theme.Font.name)
                    .foregroundStyle(Theme.ink)
                Text(highlighted)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mention.unread ? Theme.unread : Theme.background)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var context: (text: String, color: Color) {
        switch mention.place {
        case .channel(_, let root):
            ("#one-Chat · " + (root == nil ? "Allgemein" : "Thread"), Theme.coralText)
        case .discussion(_, let title):
            ("Diskussion" + (title.map { " · " + $0 } ?? ""), Theme.teal)
        case .room(_, let name):
            (name ?? "Raum", Theme.ink3)
        }
    }

    /// The message, with my name in teal on soft teal, like the preview's "@Tim".
    private var highlighted: AttributedString {
        var text = AttributedString(mention.body)
        for name in me {
            for candidate in ["@" + name, name] {
                if let range = text.range(of: candidate, options: .caseInsensitive) {
                    text[range].foregroundColor = Theme.teal
                    text[range].backgroundColor = Theme.tealSoft
                    text[range].font = .system(size: 15.5, weight: .semibold)
                    return text
                }
            }
        }
        return text
    }

    /// "09:52", "Gestern", "Mo." or "12.11.".
    static func shortTime(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.twoDigits))
    }
}
