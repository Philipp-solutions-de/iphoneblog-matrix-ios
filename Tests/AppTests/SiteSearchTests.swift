import SwiftUI
import XCTest
@testable import iphoneblog

/// The search over blog and #one (ADR-0010): the answer's highlights, where a hit opens, and the
/// model's typing pause and cancelling.
@MainActor
final class SiteSearchTests: XCTestCase {
    // MARK: Highlights

    func testMarksBecomeTealAndTheRestStaysPlain() {
        let text = SearchMarkup.attributed("… der <mark>Akku</mark> hält &amp; hält, <mark>Akkus</mark> auch")
        XCTAssertEqual(String(text.characters), "… der Akku hält & hält, Akkus auch")
        let marked = text.runs.filter { $0.attributes[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] == Theme.teal }.map { String(text[$0.range].characters) }
        XCTAssertEqual(marked, ["Akku", "Akkus"])
    }

    func testEscapedTagsStayTextAndOtherTagsGo() {
        XCTAssertEqual(SearchMarkup.plain("a &lt;mark&gt; b <b>c</b> <mark>d"), "a <mark> b c d")
        XCTAssertEqual(SearchMarkup.plain("offen <mark"), "offen <mark")
        XCTAssertEqual(SearchMarkup.plain("&quot;Zitat&quot; &#39;x&#39;"), "\"Zitat\" 'x'")
    }

    // MARK: Decoding

    /// As the live API answered on 2026-11-21, a discussion hit with room_id null.
    static let answer = Data("""
    {"q":"akku","page":1,"total":4,"counts":{"post":1,"one":0,"video":1,"link":1,"chat":0,"discussion":1},"took_ms":2,
     "hits":[
      {"id":"chat:$K","type":"discussion","label":"Diskussion","title":"„Welcome Apple HomeView“",
       "snippet":"Bitte <mark>aktu</mark>alisieren.","url":"https://www.iphoneblog.de/2026/10/13/welcome-apple-homeview/",
       "deep_link":"https://chat.iphoneblog.de/#/room/None/$K","t":null,"room_id":null,"event_id":"$K",
       "thread_root":"$Root","room_name":null,"sender_name":"Dominic","domain":null,"mentions":null,"post_id":65738,
       "published":"2026-11-17T13:16:55Z","score":0.7},
      {"id":"video:65744:0012","type":"video","label":"Video","title":"Kalenderwochen","snippet":"der <mark>Akku</mark>",
       "url":"https://www.iphoneblog.de/2026/10/15/kw/","deep_link":"https://www.iphoneblog.de/2026/10/15/kw/?t=754",
       "t":754,"post_id":65744,"published":"2026-10-15T13:31:08Z","score":0.6},
      {"id":"video:65744:0012","type":"video","label":"Video","title":"doppelt","snippet":"","score":0.5},
      {"id":"link:abc","type":"link","label":"Link","title":"Apple","snippet":"<mark>Akku</mark>","url":"https://apple.com/x",
       "deep_link":"https://apple.com/x","domain":"apple.com","published":null},
      {"id":"x:1","type":"podcast","label":"Neu","title":"unbekannt","snippet":""}
     ]}
    """.utf8)

    func testAnswerDecodesWithItsMetaAndWithoutDuplicatesOrUnknownKinds() throws {
        let page = try SiteSearchPage.prepare(Self.answer)
        XCTAssertEqual(page.total, 4)
        XCTAssertEqual(page.hits.map(\.id), ["chat:$K", "video:65744:0012", "link:abc"])
        XCTAssertEqual(page.hits[0].meta, "Dominic · 17. Nov. 2026")
        XCTAssertEqual(page.hits[1].meta, "ab 12:34 · 15. Okt. 2026")
        XCTAssertEqual(page.hits[1].seconds, 754)
        XCTAssertEqual(page.hits[2].meta, "apple.com")
        XCTAssertEqual(SiteSearchFilter.all.count(in: page.counts), 4)
        XCTAssertEqual(SiteSearchFilter.chat.count(in: page.counts), 1)
        XCTAssertEqual(SiteSearchFilter.posts.types, [.post, .one])
    }

    /// ADR-0010, "Distinct results": a hit's group size under it, by kind; nothing at 0.
    func testMoreLineUnderAGroupedHit() throws {
        XCTAssertEqual(SiteSearchPage.moreLine(0, kind: .chat), "")
        XCTAssertEqual(SiteSearchPage.moreLine(1, kind: .chat), "und 1 weitere Antwort")
        XCTAssertEqual(SiteSearchPage.moreLine(3, kind: .discussion), "und 3 weitere Antworten")
        XCTAssertEqual(SiteSearchPage.moreLine(1, kind: .video), "und 1 weitere Stelle")
        XCTAssertEqual(SiteSearchPage.moreLine(7, kind: .video), "und 7 weitere Stellen")
        XCTAssertEqual(SiteSearchPage.moreLine(2, kind: .post), "", "posts have no group")
        XCTAssertEqual(SiteSearchPage.moreLine(2, kind: .link), "")
        let page = try SiteSearchPage.prepare(Data("""
            {"total":2,"counts":{"chat":1,"video":1},"hits":[
              {"id":"chat:$A","type":"chat","title":"","snippet":"a","more":4},
              {"id":"video:1:0001","type":"video","title":"V","snippet":"b","t":3}
            ]}
            """.utf8))
        XCTAssertEqual(page.hits.map(\.more), ["und 4 weitere Antworten", ""], "missing more counts as 0")
    }

    /// A post merged with its own video and discussion (ADR-0010) shows a line for each, and
    /// each opens where a video or discussion hit opens.
    func testMergedPostCarriesVideoAndDiscussionLines() throws {
        let page = try SiteSearchPage.prepare(Data("""
            {"total":2,"counts":{"post":2},"hits":[
              {"id":"post:7","type":"post","title":"P","snippet":"a","url":"https://www.iphoneblog.de/p/","post_id":7,
               "video":{"t":754,"deep_link":"https://www.iphoneblog.de/p/?t=754","more":2},
               "discussion":{"count":3,"deep_link":"https://chat.iphoneblog.de/#/room/!blog:iphoneblog.de/$reply","thread_root":"$article"}},
              {"id":"post:8","type":"post","title":"Q","snippet":"b","video":null,"discussion":null}
            ]}
            """.utf8))
        let merged = page.hits[0], plain = page.hits[1]
        XCTAssertEqual(merged.videoLine, "Im Video ab 12:34")
        XCTAssertEqual(merged.discussionLine, "3 Antworten in der Diskussion")
        XCTAssertEqual(plain.videoLine, "")
        XCTAssertEqual(plain.discussionLine, "")
        XCTAssertNil(plain.videoHit)
        XCTAssertNil(plain.discussionHit)

        let video = try XCTUnwrap(merged.videoHit)
        XCTAssertEqual(video.kind, .video)
        XCTAssertEqual(video.seconds, 754)
        XCTAssertEqual(video.postID, 7)
        XCTAssertEqual(video.deepLink?.absoluteString, "https://www.iphoneblog.de/p/?t=754")
        let discussion = try XCTUnwrap(merged.discussionHit)
        XCTAssertEqual(discussion.kind, .discussion)
        XCTAssertEqual(discussion.roomID, "!blog:iphoneblog.de")
        XCTAssertEqual(discussion.eventID, "$reply")
        XCTAssertEqual(discussion.threadRoot, "$article", "the discussion opens by the article's root")
        XCTAssertEqual(Router.target(for: discussion, chat: false), .discussion(rootEventID: "$article"))

        var one = merged
        one.discussionCount = 1
        XCTAssertEqual(one.discussionLine, "1 Antwort in der Diskussion")
        XCTAssertEqual(SiteSearchHit.clock(3725), "1:02:05")
        XCTAssertEqual(SiteSearchHit.clock(5), "0:05")
    }

    /// Main-thread budget (WordPress docs/chat.md, "Performance"): a page's preparation runs off
    /// the main thread anyway; even so it stays far under one 120 Hz frame.
    func testPreparingAFullPageTakesUnderAFrame() throws {
        var hits: [String] = []
        for index in 0..<20 {
            hits.append("""
            {"id":"post:\(index)","type":"post","label":"Beitrag","title":"Titel \(index) mit <mark>Akku</mark>",
             "snippet":"\(String(repeating: "Wort ", count: 30))<mark>Akku</mark> \(String(repeating: "mehr ", count: 10)) &amp; <mark>Akku</mark>",
             "url":"https://www.iphoneblog.de/\(index)/","published":"2026-11-17T13:16:55Z"}
            """)
        }
        let data = Data("{\"total\":20,\"hits\":[\(hits.joined(separator: ","))]}".utf8)
        _ = try SiteSearchPage.prepare(data)
        var best = Double.infinity
        for _ in 0..<5 {
            let start = ContinuousClock.now
            _ = try SiteSearchPage.prepare(data)
            let elapsed = ContinuousClock.now - start
            best = min(best, Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        XCTAssertLessThan(best, 8, "preparing 20 hits took \(best) ms")
    }

    // MARK: Where a hit opens

    private func hit(_ kind: SiteSearchHit.Kind, room: String? = nil, event: String? = nil, root: String? = nil,
                     url: String? = "https://www.iphoneblog.de/2026/11/01/a/", deep: String? = nil,
                     seconds: Int? = nil, post: Int? = 1) -> SiteSearchHit {
        SiteSearchHit(id: "x", kind: kind, label: "", title: "", snippet: "", meta: "", url: url.flatMap(URL.init(string:)),
                      deepLink: deep.flatMap(URL.init(string:)), seconds: seconds, roomID: room, eventID: event,
                      threadRoot: root, postID: post, locked: false)
    }

    func testEachKindOpensWhereItLives() throws {
        let article = try XCTUnwrap(URL(string: "https://www.iphoneblog.de/2026/11/01/a/"))
        let atT = try XCTUnwrap(URL(string: "https://www.iphoneblog.de/2026/11/01/a/?t=90"))
        XCTAssertEqual(Router.target(for: hit(.post), chat: false), .blogPage(article))
        XCTAssertEqual(Router.target(for: hit(.one), chat: true), .blogPage(article))
        XCTAssertEqual(Router.target(for: hit(.video, deep: atT.absoluteString, seconds: 90, post: 7), chat: true),
                       .video(postID: 7, seconds: 90, page: atT))
        // Outside #one the episode list is closed to the reader: the article at the second.
        XCTAssertEqual(Router.target(for: hit(.video, deep: atT.absoluteString, seconds: 90, post: 7), chat: false), .blogPage(atT))
        XCTAssertEqual(Router.target(for: hit(.chat, room: "!r", event: "$e"), chat: true), .message(roomID: "!r", eventID: "$e"))
        XCTAssertEqual(Router.target(for: hit(.chat, room: "!r", event: "$e", root: "$root"), chat: true),
                       .thread(roomID: "!r", rootEventID: "$root"))
        XCTAssertEqual(Router.target(for: hit(.chat, room: "!r", event: "$root", root: "$root"), chat: true),
                       .message(roomID: "!r", eventID: "$root"))
        XCTAssertEqual(Router.target(for: hit(.discussion, event: "$e", root: "$root"), chat: false), .discussion(rootEventID: "$root"))
        XCTAssertEqual(Router.target(for: hit(.link, url: "https://apple.com/x", deep: "https://apple.com/x"), chat: true),
                       .outside(try XCTUnwrap(URL(string: "https://apple.com/x"))))
    }

    func testOpeningMovesTheTabs() throws {
        let router = Router()
        router.showSiteSearch = true
        let page = try XCTUnwrap(URL(string: "https://www.iphoneblog.de/x/"))
        router.open(.video(postID: 7, seconds: 90, page: page))
        XCTAssertEqual(router.tab, .chat)
        XCTAssertEqual(router.chatPath, [.video(postID: 7, seconds: 90, page: page)])
        router.open(.blogPage(page))
        XCTAssertEqual(router.tab, .blog)
        XCTAssertEqual(router.blogPageRequest, page)
        router.open(.discussion(rootEventID: "$root"))
        XCTAssertEqual(router.blogPath, [.thread(rootEventID: "$root")])
    }

    func testBlogAddressesFollowTheBlogTheTabShows() throws {
        let start = try XCTUnwrap(URL(string: "https://beta.iphoneblog.de/?app=1"))
        let fixture = try XCTUnwrap(URL(string: "http://127.0.0.1:8793/blog/?app=1"))
        let post = try XCTUnwrap(URL(string: "https://www.iphoneblog.de/2026/11/01/a/?t=5"))
        XCTAssertEqual(BlogLinks.onBlog(post, start: start).absoluteString, "https://beta.iphoneblog.de/2026/11/01/a/?t=5")
        XCTAssertEqual(BlogLinks.onBlog(post, start: fixture).absoluteString, "http://127.0.0.1:8793/2026/11/01/a/?t=5")
        let apple = try XCTUnwrap(URL(string: "https://apple.com/x"))
        XCTAssertEqual(BlogLinks.onBlog(apple, start: start), apple)
    }

    // MARK: Typing, cancelling, tokens

    /// Records each request; answers after `delay(query)`.
    private final class Transport: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [URLRequest] = []
        var statuses: [Int] = []
        var delay: @Sendable (String) -> Duration = { _ in .zero }

        var requests: [URLRequest] { lock.withLock { seen } }
        var queries: [String] { requests.map { Self.query($0) } }

        static func query(_ request: URLRequest) -> String {
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? "" // swiftlint:disable:this force_unwrapping
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let status: Int = lock.withLock {
                seen.append(request)
                return statuses.isEmpty ? 200 : statuses.removeFirst()
            }
            try await Task.sleep(for: delay(Self.query(request)))
            let query = Self.query(request)
            let body = """
            {"total":1,"counts":{"post":1},"hits":[{"id":"post:\(query)","type":"post","label":"Beitrag","title":"\(query)","snippet":""}]}
            """
            // swiftlint:disable:next force_unwrapping
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func model(_ transport: Transport, token: String? = nil) -> SiteSearchModel {
        let model = SiteSearchModel(client: SiteSearchClient(endpoint: URL(string: "https://chat.example/_iphoneblog/v1/search")!, // swiftlint:disable:this force_unwrapping
                                                             token: { token }, refresh: { }, transport: { try await transport.send($0) }))
        return model
    }

    private func wait(_ timeout: TimeInterval = 3, until condition: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testTypingSendsOneRequestAfterThePause() async {
        let transport = Transport()
        let model = model(transport)
        for prefix in ["a", "ak", "akk", "akku"] {
            model.query = prefix
            try? await Task.sleep(for: .milliseconds(30))
        }
        await wait { model.state == .done }
        XCTAssertEqual(transport.queries, ["akku"])
        XCTAssertEqual(model.hits.map(\.id), ["post:akku"])
    }

    func testAStaleAnswerIsDropped() async {
        let transport = Transport()
        transport.delay = { $0 == "akku" ? .milliseconds(400) : .zero }
        let model = model(transport)
        model.query = "akku"
        await wait { transport.queries.count == 1 }
        model.query = "akkus"
        await wait { model.state == .done }
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.hits.map(\.id), ["post:akkus"])
    }

    func testAChipSearchesAtOnceWithItsTypes() async throws {
        let transport = Transport()
        let model = model(transport)
        model.query = "akku"
        await wait { model.state == .done }
        model.filter = .chat
        await wait { transport.requests.count == 2 }
        let types = URLComponents(url: try XCTUnwrap(transport.requests.last?.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "types" }?.value
        XCTAssertEqual(types, "chat,discussion")
    }

    func testARefusedTokenIsRefreshedThenDropped() async throws {
        let transport = Transport()
        transport.statuses = [401, 401, 200]
        let client = SiteSearchClient(endpoint: try XCTUnwrap(URL(string: "https://chat.example/s")), token: { "t" }, refresh: { },
                                      transport: { try await transport.send($0) })
        let page = try await client.search("akku", types: nil, page: 1)
        XCTAssertEqual(page.hits.count, 1)
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer t", "Bearer t", nil])
    }

    func testOneLetterSearchesNothing() async {
        let transport = Transport()
        let model = model(transport)
        model.query = "a"
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(model.state, .idle)
    }
}
