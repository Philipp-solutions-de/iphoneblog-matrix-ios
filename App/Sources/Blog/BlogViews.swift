import SwiftUI

/// The Blog tab (decisions 2026-11-15): the blog's own pages in a web view (`?app=1`, no site
/// chrome), and under each article a "Diskussion" link that opens the article's Matrix thread
/// natively. Members write there; everyone else reads, signed in or not.
struct BlogTab: View {
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?
    @ObservedObject var guestFeed: GuestBlogFeed
    @StateObject private var web = BlogWebModel()

    var body: some View {
        NavigationStack(path: $router.blogPath) {
            BlogHome(web: web)
                .navigationTitle("Blog")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { value in
                    if let route = BlogRoute(value) {
                        DiscussionView(route: route, session: session, guestFeed: guestFeed, router: router, web: web)
                    } else {
                        ContentUnavailableView("Nicht gefunden", systemImage: "questionmark.bubble")
                    }
                }
        }
        .onAppear {
            web.onDiscussion = { [weak router] permalink in
                router?.blogPath.append(BlogRoute.article(permalink).value)
            }
            #if DEBUG
            // Screenshot runs: open an article's Diskussion at launch (IPHONEBLOG_BLOG_OPEN=<permalink>).
            if router.blogPath.isEmpty, let open = ProcessInfo.processInfo.environment["IPHONEBLOG_BLOG_OPEN"],
               let url = URL(string: open) {
                router.blogPath = [BlogRoute.article(url).value]
            }
            #endif
        }
    }
}

/// The logo on top, the blog below.
private struct BlogHome: View {
    @ObservedObject var web: BlogWebModel

    var body: some View {
        BlogWebView(model: web)
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.background)
            .overlay {
                switch web.phase {
                case .loading:
                    ProgressView()
                case .failed:
                    ContentUnavailableView {
                        Label("Blog nicht erreichbar", systemImage: "wifi.slash")
                    } description: {
                        Text("Die Seite lässt sich gerade nicht laden.")
                    } actions: {
                        Button("Nochmal versuchen") { web.reload() }
                            .buttonStyle(.borderedProminent)
                    }
                    .background(Theme.background)
                case .ready:
                    EmptyView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Button { web.goHome() } label: {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Theme.Discussion.logoSize, height: Theme.Discussion.logoSize)
                        .frame(maxWidth: .infinity, minHeight: Theme.Discussion.logoBarHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("iPhoneBlog.de, zum Anfang")
                .background(Theme.background)
                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
            }
    }
}

// MARK: - Diskussion

/// One article's thread: the article on top, the replies below. Members get the conversation
/// views with a composer; everyone else reads the public thread file and is offered sign-in or #one.
struct DiscussionView: View {
    let route: BlogRoute
    let session: ChatSession?
    let guestFeed: GuestBlogFeed
    @ObservedObject var router: Router
    let web: BlogWebModel

    @State private var phase: Phase = .looking
    @State private var article: BlogArticle?
    @State private var replies: [BlogReply] = []

    enum Phase: Equatable {
        case looking
        case found(rootEventID: String)
        case none
        case failed
    }

    var body: some View {
        VStack(spacing: 0) {
            DiscussionHeader(title: title, replyCount: article?.replyCount, readArticle: articleURL.map { url in
                { readArticle(url) }
            })
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task(id: route) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .looking:
            ProgressView()
        case .failed:
            ContentUnavailableView {
                Label("Nicht erreichbar", systemImage: "wifi.slash")
            } description: {
                Text("Die Diskussion lässt sich gerade nicht laden.")
            } actions: {
                Button("Nochmal versuchen") { Task { await load() } }
            }
        case .none:
            ContentUnavailableView("Noch keine Diskussion", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Zu diesem Artikel gibt es noch keinen Thread. Er erscheint, sobald der Artikel im Chat steht."))
        case .found(let root):
            if let session {
                SignedInDiscussion(session: session, rootEventID: root, replies: replies, router: router)
            } else {
                ReaderDiscussion(replies: replies, signedIn: false, router: router)
            }
        }
    }

    private var title: String {
        article?.title ?? web.pageTitle.flatMap { $0.isEmpty ? nil : Self.trimSiteName($0) } ?? "Artikel"
    }

    private var articleURL: URL? {
        if case .article(let url) = route { return url }
        return article?.link
    }

    private func readArticle(_ url: URL) {
        web.open(url)
        router.blogPath = []
    }

    private func load() async {
        phase = .looking
        do {
            let root: String
            switch route {
            case .thread(let id):
                root = id
            case .article(let permalink):
                guard let found = try await BlogLinkStore.shared.rootEventID(for: permalink) else {
                    phase = .none
                    return
                }
                root = found
            }
            // The public thread file gives title and replies to everyone; members' replies come
            // live through the SDK, so a member does not wait for it.
            phase = .found(rootEventID: root)
            if let (article, replies) = try? await guestFeed.thread(root) {
                self.article = article
                self.replies = replies
            } else if session == nil {
                phase = .failed
            }
        } catch {
            phase = .failed
        }
    }

    /// "Titel – iPhoneBlog.de" → "Titel".
    static func trimSiteName(_ title: String) -> String {
        for separator in [" – ", " | ", " - "] {
            if let range = title.range(of: separator, options: .backwards) {
                return String(title[..<range.lowerBound])
            }
        }
        return title
    }
}

/// "DISKUSSION", the article's title, the reply count and "Artikel lesen".
private struct DiscussionHeader: View {
    let title: String
    let replyCount: Int?
    let readArticle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diskussion")
                .font(Theme.Discussion.eyebrow)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(Theme.ink2)
            Text(title)
                .font(Theme.Discussion.title)
                .foregroundStyle(Theme.teal)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                if let replyCount {
                    Text(replyCount == 1 ? "1 Antwort" : "\(replyCount) Antworten")
                        .foregroundStyle(Theme.ink2)
                }
                if replyCount != nil, readArticle != nil {
                    Text("·").foregroundStyle(Theme.ink2).accessibilityHidden(true)
                }
                if let readArticle {
                    Button("Artikel lesen", action: readArticle)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.teal)
                }
            }
            .font(Theme.Discussion.meta)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Discussion.margin)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

/// Signed in: a #one member writes in the conversation views; anyone else reads.
private struct SignedInDiscussion: View {
    @ObservedObject var session: ChatSession
    let rootEventID: String
    let replies: [BlogReply]
    @ObservedObject var router: Router

    var body: some View {
        if session.isOneMember, let roomID = session.blogRoomID {
            ChatScreens.provider.threadScreen(roomID: roomID, rootEventID: rootEventID, host: session)
        } else {
            ReaderDiscussion(replies: replies, signedIn: true, router: router)
        }
    }
}

/// The replies, read-only, and the offer where a composer would be.
private struct ReaderDiscussion: View {
    let replies: [BlogReply]
    let signedIn: Bool
    @ObservedObject var router: Router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if replies.isEmpty {
                    Text("Noch keine Antworten.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.ink2)
                        .padding(Theme.Discussion.margin)
                }
                ForEach(replies) { reply in
                    ReplyRow(reply: reply)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ReaderOffer(signedIn: signedIn, router: router)
        }
    }
}

private struct ReplyRow: View {
    let reply: BlogReply

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            InitialsAvatar(name: reply.sender, size: Theme.Discussion.avatar)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reply.sender)
                        .font(Theme.Discussion.sender)
                        .foregroundStyle(Theme.ink)
                    Text(DiscussionTime.text(reply.date))
                        .font(Theme.Discussion.time)
                        .foregroundStyle(Theme.ink2)
                }
                Text(reply.body)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Discussion.margin)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// "Mitlesen kann jeder. Mitschreiben können Mitglieder von #one." with the way in.
private struct ReaderOffer: View {
    let signedIn: Bool
    @ObservedObject var router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink2)
                    .accessibilityHidden(true)
                Text(Self.message)
                    .font(Theme.Discussion.offer)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if !signedIn {
                    Button { router.showSignIn = true } label: {
                        Text("Anmelden").frame(maxWidth: .infinity, minHeight: Theme.Discussion.buttonHeight)
                    }
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .background(Theme.teal, in: RoundedRectangle(cornerRadius: Theme.Size.corner))
                }
                Button {
                    if let url = URL(string: Brand.oneOfferURL) { router.presentedURL = url }
                } label: {
                    Text("#one werden").frame(maxWidth: .infinity, minHeight: Theme.Discussion.buttonHeight)
                }
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Discussion.coralText)
                .overlay(RoundedRectangle(cornerRadius: Theme.Size.corner).strokeBorder(Theme.coral, lineWidth: 1.5))
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Discussion.offerCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.Discussion.offerCorner).strokeBorder(Theme.line))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private static var message: AttributedString {
        var text = AttributedString("Mitlesen kann jeder. Mitschreiben können Mitglieder von ")
        var one = AttributedString("#one")
        one.foregroundColor = Theme.coral
        one.font = Theme.Discussion.offer.weight(.semibold)
        text += one
        text += AttributedString(".")
        return text
    }
}

/// "10:42" today, "Gestern, 11:48", then "12. Nov., 11:48".
enum DiscussionTime {
    static func text(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let german = Locale(identifier: "de_DE")
        let time = date.formatted(.dateTime.hour().minute().locale(german))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Gestern, \(time)"
        }
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(german))
        return "\(day), \(time)"
    }
}
