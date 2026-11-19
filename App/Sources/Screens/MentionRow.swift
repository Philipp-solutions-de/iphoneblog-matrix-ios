import SwiftUI

/// One mention as "Für dich" lists it: who, where, when, and the message with my name marked.
struct MentionRow: View {
    let mention: MentionsModel.Mention
    let me: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MemberAvatar(userID: mention.senderID, name: mention.senderName, roomID: mention.roomID,
                         size: Theme.Size.chatAvatar)
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

    /// The place as words, for the filter.
    static func placeName(_ place: MentionsModel.Mention.Place) -> String {
        switch place {
        case .channel(_, let root, let name): "#one " + (name ?? "") + (root == nil ? "" : " Thread")
        case .discussion(_, let title): "Diskussion " + (title ?? "")
        case .room(_, let name): name ?? ""
        }
    }

    private var context: (text: String, color: Color) {
        switch mention.place {
        case .channel(_, let root, let name):
            ("#one" + (name.map { " · " + $0 } ?? "") + (root == nil ? "" : " · Thread"), Theme.teal)
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
