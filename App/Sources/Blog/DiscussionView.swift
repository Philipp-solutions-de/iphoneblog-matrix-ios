import SwiftUI

/// An article's discussion (previews 2a and 2b): "DISKUSSION", the article's title,
/// "n Antworten", then the thread. #one members read and write in the
/// conversation views; everyone else reads, with a panel that says who can write.
struct DiscussionView: View {
    let route: Router.DiscussionRoute
    /// Nil while signed out.
    let session: ChatSession?
    @ObservedObject var router: Router

    @State private var rootEventID: String?
    @State private var page: GuestAPI.ThreadPage?
    @State private var state: LoadState = .loading

    /// `signInToStart`: an article without a thread, and a reader without an account to have
    /// one made (the server makes threads only for signed-in calls).
    enum LoadState { case loading, ready, signInToStart, unavailable }

    private var isMember: Bool { session?.isOneMember ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            content
        }
        .background(Theme.background)
        // The system back button ("‹ Blog", from the blog's title): a custom one would switch
        // off the swipe from the left edge back to the blog.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task(id: route) { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISKUSSION")
                .font(Theme.Font.overline)
                .tracking(0.5)
                .foregroundStyle(Theme.ink3)
            // No thread file yet (a new thread, or none): no empty title line.
            if page != nil || state == .loading {
                Text(page?.root.title ?? " ")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.tealBright)
                    .fixedSize(horizontal: false, vertical: true)
                    .redacted(reason: page == nil ? .placeholder : [])
            }
            // Members see the live count under the thread's first message; the file's count
            // lags behind the chat by up to a minute.
            if let page, session == nil {
                Text(page.root.replyCount == 1 ? "1 Antwort" : "\(page.root.replyCount) Antworten")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxHeight: .infinity)
        case .signInToStart:
            ContentUnavailableView {
                Label("Noch keine Antworten", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Anmelden, um mitzudiskutieren.")
            } actions: {
                Button("Anmelden") { router.showSignIn = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.coralButton)
            }
        case .unavailable:
            ContentUnavailableView {
                Label("Nicht erreichbar", systemImage: "wifi.slash")
            } description: {
                Text("Die Diskussion lässt sich gerade nicht laden.")
            } actions: {
                Button("Nochmal versuchen") { Task { await load() } }
                    .tint(Theme.teal)
            }
        case .ready:
            if isMember, let session, let roomID = session.blogRoomID, let rootEventID {
                // Members: the conversation views, with the composer that answers in the thread.
                ChatScreens.provider.discussionScreen(roomID: roomID, rootEventID: rootEventID, host: session)
            } else {
                readOnly
            }
        }
    }

    /// The replies, readable by everyone, and the panel that says who can write.
    private var readOnly: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(page?.replies ?? [], id: \.eventId) { reply in
                    ReplyRow(name: reply.senderName, date: Date(milliseconds: reply.ts), text: reply.body, html: reply.formattedBody,
                             media: reply.media) { router.presentedURL = $0 }
                }
                if page?.replies.isEmpty ?? true {
                    Text("Noch keine Antworten.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, Theme.Space.page)
                        .padding(.vertical, Theme.Space.row)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 180)
        }
        .overlay(alignment: .bottom) {
            ReaderPanel(signedIn: session != nil, router: router)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: Loading

    private func load() async {
        state = .loading
        let store = DiscussionStore.shared
        switch route {
        case .article(let url):
            do {
                rootEventID = try await store.rootEventID(for: url, token: session.flatMap { try? $0.client.session().accessToken })
            } catch {
                // Not "no discussion", which would be wrong and final: try again.
                state = .unavailable
                return
            }
        case .thread(let id):
            rootEventID = id
        }
        guard let rootEventID else {
            state = .signInToStart
            return
        }
        // A thread made a moment ago has no file yet; the bot writes it within a minute.
        page = try? await store.thread(rootEventID)
        state = .ready
        var waited = 0
        while page == nil, waited < 6, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            waited += 1
            page = try? await store.thread(rootEventID)
        }
    }
}

/// A reply's picture for readers: the server's thumbnail at its own proportions, at most the
/// chat's media width; a tap opens the full picture.
struct ReplyPicture: View {
    let media: GuestAPI.Media
    let label: String
    let action: () -> Void

    private var ratio: CGFloat {
        let w = media.thumbnailW ?? media.w ?? 4, h = media.thumbnailH ?? media.h ?? 3
        return CGFloat(max(w, 1)) / CGFloat(max(h, 1))
    }

    var body: some View {
        Button(action: action) {
            AsyncImage(url: media.thumbnailUrl ?? media.url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Theme.surface
                }
            }
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: Theme.Chat.mediaWidth, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel(label)
    }
}

/// One reply: round initials, name, time, text or picture (preview 2b).
struct ReplyRow: View {
    let name: String
    let date: Date
    let text: String
    var html: String?
    var media: GuestAPI.Media?
    /// Opens the full picture.
    var open: (URL) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.rowGap) {
            InitialsAvatar(name: name, size: Theme.Size.avatar)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name).font(Theme.Font.name).foregroundStyle(Theme.ink)
                    Text(ReplyRow.format(date)).font(Theme.Font.time).foregroundStyle(Theme.ink3)
                }
                if let media {
                    ReplyPicture(media: media, label: text) { open(media.url) }
                } else {
                    Text(ReplyText.attributed(body: text, formattedBody: html)).font(Theme.Font.body).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.row)
        .accessibilityElement(children: .combine)
    }

    /// "10:42", "Gestern, 11:48", "Mo., 09:12" or "12.11., 09:12".
    static func format(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Gestern, \(time)" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated)) + ", " + time
        }
        return date.formatted(.dateTime.day().month(.twoDigits)) + ", " + time
    }
}

/// "Mitlesen kann jeder. Mitschreiben können Mitglieder von #one." with the way in.
struct ReaderPanel: View {
    let signedIn: Bool
    @ObservedObject var router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock").foregroundStyle(Theme.ink3)
                (Text("Mitlesen kann jeder. Mitschreiben können Mitglieder von ")
                 + Text("#one").foregroundStyle(Theme.coral).fontWeight(.semibold)
                 + Text("."))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink2)
            }
            HStack(spacing: 10) {
                if !signedIn {
                    Button { router.showSignIn = true } label: {
                        Text("Anmelden").frame(maxWidth: .infinity, minHeight: Theme.Size.smallButtonHeight)
                    }
                    .buttonStyle(FilledButton(fill: Theme.coralButton))
                }
                Button {
                    if let url = URL(string: Brand.oneOfferURL) { router.presentedURL = url }
                } label: {
                    Text("#one werden").frame(maxWidth: .infinity, minHeight: Theme.Size.smallButtonHeight)
                }
                .buttonStyle(OutlineButton(stroke: Theme.coral, text: Theme.coralText))
            }
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.Size.panelCorner).stroke(Theme.line))
    }
}

/// White text on a filled, rounded button.
struct FilledButton: ButtonStyle {
    let fill: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Coloured text in a coloured outline.
struct OutlineButton: ButtonStyle {
    let stroke: Color
    let text: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(text)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
