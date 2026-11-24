import SwiftUI

/// One mention as "Für dich" lists it: who, where, when, and the message with its mentions marked.
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
                MentionPill.text(highlighted)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .textRenderer(MentionPill.Renderer())
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

    private var highlighted: AttributedString {
        Self.highlight(mention.body, mentioned: mention.mentioned, me: me)
    }

    /// The message with its mentions marked as the room timeline marks them (Philip,
    /// 2026-11-20): a mention of me white on solid teal, anyone else's teal on soft teal, drawn
    /// as the timeline's rounded pill (``MentionPill``). Without
    /// mention links (a client that typed "@Name" as plain text) my own name is still marked.
    static func highlight(_ body: String, mentioned: [String], me: [String]) -> AttributedString {
        var text = AttributedString(body)
        let mine = Set(me.map { $0.lowercased() })
        func mark(_ range: Range<AttributedString.Index>, isMe: Bool) {
            text[range].foregroundColor = isMe ? .white : Theme.teal
            text[range][MentionPill.Key.self] = isMe
            text[range].font = .system(size: 15.5, weight: .semibold)
        }
        if !mentioned.isEmpty {
            for name in mentioned {
                let isMe = mine.contains(String(name.dropFirst()).lowercased())
                var from = text.startIndex
                while from < text.endIndex, let range = text[from...].range(of: name) {
                    mark(range, isMe: isMe)
                    from = range.upperBound
                }
            }
            return text
        }
        for name in me {
            for candidate in ["@" + name, name] {
                if let range = text.range(of: candidate, options: .caseInsensitive) {
                    mark(range, isMe: true)
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

/// The rounded pill behind a mention in a preview, as the room timeline draws it (Element X's
/// `PillView`: a capsule, the text a little inside). An attributed string's `backgroundColor`
/// draws a square box (Philip, #bugs 2026-11-21: "Highlighted usernames sind eckig"), so the
/// mention carries ``Key`` and ``Renderer`` draws the capsule behind its glyphs; the text still
/// wraps and keeps its line limit.
enum MentionPill {
    /// On a mention: true for my own name (solid teal), false for anyone else's (soft teal).
    enum Key: AttributedStringKey {
        typealias Value = Bool
        static let name = "de.iphoneblog.mentionPill"
    }

    /// What the renderer reads from a run.
    struct Attribute: TextAttribute {
        let isMe: Bool
    }

    /// The room pill's padding (Element X's `PillView`): 4 pt before the name, 6 after. Philip,
    /// build 275: "Sie sind rund, aber nicht identisch mit denen im Raum. Da fehlt etwas padding
    /// links und rechts" (a hair space either side was about 1.5 pt).
    static let leading: CGFloat = 4
    static let trailing: CGFloat = 6

    /// The highlighted message as one Text, each mention a run of its own between two fixed-width
    /// spaces about as wide as the padding (U+2005, a quarter em, before; U+2004, a third, after).
    /// The renderer draws the capsule over them: the name sits in the room's padding, and the
    /// words beside it keep their distance. Padding inside the run moved the name but not the
    /// capsule, which follows the glyphs, and SwiftUI drops kerning on a lone zero-width
    /// character (2026-11-22).
    static func text(_ string: AttributedString) -> Text {
        var result = Text(verbatim: "")
        for run in string.runs {
            let part = AttributedString(string[run.range])
            if let isMe = run[Key.self] {
                result = Text("\(result)\u{2005}\(Text(part).customAttribute(Attribute(isMe: isMe)))\u{2004}")
            } else {
                result = Text("\(result)\(Text(part))")
            }
        }
        return result
    }

    struct Renderer: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                for run in line {
                    if let pill = run[Attribute.self] {
                        let glyphs = run.typographicBounds.rect
                        let box = CGRect(x: glyphs.minX - MentionPill.leading, y: glyphs.minY - 1,
                                         width: glyphs.width + MentionPill.leading + MentionPill.trailing,
                                         height: glyphs.height + 2)
                        context.fill(Capsule().path(in: box), with: .color(pill.isMe ? Theme.badge : Theme.tealSoft))
                    }
                    context.draw(run)
                }
            }
        }
    }
}
