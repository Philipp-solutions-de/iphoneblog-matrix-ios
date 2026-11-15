import MatrixRustSDK
import SwiftUI

/// The Blog tab: one card per article, newest activity first. A tap opens its thread:
/// signed in, the conversation views (members reply, others read); signed out, a read-only
/// thread with a sign-in offer where replying would start.
struct BlogTab: View {
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?
    @ObservedObject var guestFeed: GuestBlogFeed

    var body: some View {
        NavigationStack(path: $router.blogPath) {
            Group {
                if let session, let feed = session.blogFeed {
                    BlogList(feed: feed, client: session.client)
                } else {
                    BlogList(feed: guestFeed, client: nil)
                }
            }
            .navigationDestination(for: String.self) { rootEventID in
                if let session, let roomID = session.blogRoomID {
                    ChatScreens.provider.threadScreen(roomID: roomID, rootEventID: rootEventID, host: session)
                } else {
                    GuestThreadView(feed: guestFeed, rootEventID: rootEventID, router: router)
                }
            }
        }
    }
}

/// The list of article cards, from either feed.
private struct BlogList<Feed: BlogFeed & ObservableObject>: View {
    @ObservedObject var feed: Feed
    let client: Client?

    var body: some View {
        List {
            Section {
                ForEach(feed.articles) { article in
                    // A hidden link: the card keeps the full width, without the list's arrow.
                    ArticleCard(article: article, client: client)
                        .background(NavigationLink(value: article.id) { EmptyView() }.opacity(0))
                    .listRowSeparator(.visible, edges: .bottom)
                    .listRowSeparatorTint(Theme.Blog.divider)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .listRowInsets(EdgeInsets(top: Theme.Blog.cardGap / 2, leading: Theme.Space.page,
                                              bottom: Theme.Blog.cardGap / 2, trailing: Theme.Space.page))
                    .listRowBackground(Color.clear)
                    .onAppear {
                        if article.id == feed.articles.last?.id { Task { await feed.loadMore() } }
                    }
                }
            } header: {
                Text(Brand.appName)
                    .font(Theme.Font.screenTitle)
                    .foregroundStyle(Theme.ink)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await feed.load() }
        .overlay {
            switch feed.state {
            case .loading where feed.articles.isEmpty:
                ProgressView()
            case .unavailable(let reason):
                ContentUnavailableView("Gerade keine Artikel", systemImage: "newspaper", description: Text(reason))
            case .ready where feed.articles.isEmpty:
                ContentUnavailableView("Noch keine Artikel", systemImage: "newspaper",
                                       description: Text("Sobald ein Artikel erscheint, steht er hier."))
            default:
                EmptyView()
            }
        }
        .task { if feed.articles.isEmpty { await feed.load() } }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One article in the feed: the picture large, the title, two lines of teaser, then how
/// many replied, who replied last and when. Values in `Theme.Blog`.
struct ArticleCard: View {
    let article: BlogArticle
    let client: Client?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Blog.cardInnerGap) {
            ArticleImage(article: article, client: client)
            Text(article.title)
                .font(Theme.Blog.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let teaser = article.teaser, !teaser.isEmpty {
                Text(teaser)
                    .font(Theme.Blog.teaser)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if !article.repliers.isEmpty {
                    ReplierStack(repliers: Array(article.repliers.prefix(Theme.Blog.maxRepliers)))
                }
                if article.replyCount > 0 {
                    Text(article.replyCount == 1 ? "1 Antwort" : "\(article.replyCount) Antworten")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.teal)
                    Text("·").foregroundStyle(Theme.ink3)
                }
                Text(article.latestReply ?? article.date, format: .relative(presentation: .named))
                    .foregroundStyle(Theme.ink3)
            }
            .font(Theme.Blog.meta)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The last repliers' faces, overlapping, newest in front.
private struct ReplierStack: View {
    let repliers: [BlogArticle.Replier]

    var body: some View {
        HStack(spacing: -Theme.Blog.replierAvatar / 3) {
            ForEach(Array(repliers.enumerated()), id: \.offset) { index, replier in
                Group {
                    if let url = replier.avatarURL {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                            InitialsAvatar(name: replier.name, size: Theme.Blog.replierAvatar)
                        }
                    } else {
                        InitialsAvatar(name: replier.name, size: Theme.Blog.replierAvatar)
                    }
                }
                .frame(width: Theme.Blog.replierAvatar, height: Theme.Blog.replierAvatar)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                .zIndex(Double(repliers.count - index))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The article's picture, full card width at 16:9: from the web while signed out, through the
/// SDK while signed in. No picture, no space.
private struct ArticleImage: View {
    let article: BlogArticle
    let client: Client?
    @State private var image: UIImage?

    private var hasImage: Bool { article.imageURL != nil || article.imageSource != nil }

    var body: some View {
        if hasImage {
            Color.clear
                .aspectRatio(Theme.Blog.imageAspect, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let url = article.imageURL {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.surface }
                    } else {
                        Theme.surface
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Blog.imageCorner))
                .task(id: article.imageSource) {
                    guard let client, let source = article.imageSource?.source,
                          let data = try? await client.getMediaThumbnail(mediaSource: source, width: 1200, height: 675) else { return }
                    image = UIImage(data: data)
                }
        }
    }
}

/// An article thread for someone not signed in: the article, the replies, and an offer to sign
/// in where the reply field would be.
struct GuestThreadView: View {
    let feed: GuestBlogFeed
    let rootEventID: String
    @ObservedObject var router: Router
    @State private var article: BlogArticle?
    @State private var replies: [BlogReply] = []
    @State private var failed = false

    var body: some View {
        List {
            if let article {
                VStack(alignment: .leading, spacing: 10) {
                    ArticleCard(article: article, client: nil)
                    if let link = article.link {
                        Button("Artikel lesen") { router.presentedURL = link }
                            .font(.body.weight(.semibold))
                    }
                }
                .listRowSeparator(.hidden)
                Section {
                    ForEach(replies) { reply in
                        HStack(alignment: .top, spacing: 11) {
                            InitialsAvatar(name: reply.sender, size: Theme.Size.headerAvatar)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text(reply.sender).font(.system(size: 15.5, weight: .semibold))
                                    Text(reply.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(Theme.ink3)
                                }
                                Text(reply.body).font(Theme.Font.body).foregroundStyle(Theme.ink)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    if !replies.isEmpty { SectionHeader(replies.count == 1 ? "1 Antwort" : "\(replies.count) Antworten") }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if failed {
                ContentUnavailableView("Nicht erreichbar", systemImage: "wifi.slash",
                                       description: Text("Der Thread lässt sich gerade nicht laden."))
            } else if article == nil {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { router.showSignIn = true } label: {
                Text("Anmelden, um mitzureden")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Size.corner + 1))
            .padding(.horizontal, Theme.Space.page)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                (article, replies) = try await feed.thread(rootEventID)
            } catch {
                failed = true
            }
        }
    }
}
