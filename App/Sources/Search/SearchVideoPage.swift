import SwiftUI

/// A video passage from the search: the episode's page, playing from the passage's first
/// second. The episode comes from the list the hub loads, a few pages further back if needed;
/// one the list does not hold opens as the article in the Blog tab, at `?t=` (the website's
/// player starts there).
struct SearchVideoPage: View {
    let postID: Int
    let seconds: Int
    let page: URL?
    @ObservedObject var episodes: EpisodesModel
    @ObservedObject var players: EpisodePlayers
    @ObservedObject var router: Router
    @State private var episode: Episode?
    @State private var missing = false

    /// How many pages of 30 it reads before it gives up: the newest 300 episodes.
    static let pageLimit = 10

    var body: some View {
        Group {
            if let episode {
                EpisodeView(episode: episode, player: players.player(for: episode)) { [players, router] in
                    if !router.chatPath.contains(where: { if case .video = $0 { return true }; return false }) { players.close(episode) }
                }
            } else if missing {
                ContentUnavailableView {
                    Label("Video nicht gefunden", systemImage: "play.slash")
                } description: {
                    Text("Im Artikel lässt es sich ansehen.")
                } actions: {
                    if let page {
                        Button("Im Blog öffnen") { router.open(.blogPage(page)) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.teal)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .background(Theme.background)
        .task(id: postID) { await find() }
    }

    private func find() async {
        if episode != nil { return }
        if !episodes.hasLoaded { await episodes.load() }
        var pages = 0
        while true {
            if let found = episodes.episodes.first(where: { $0.postID == postID }) {
                episode = found
                players.player(for: found).play(from: Double(seconds))
                return
            }
            let before = episodes.episodes.count
            guard pages < Self.pageLimit else { break }
            await episodes.loadMore()
            pages += 1
            if episodes.episodes.count == before { break }
        }
        missing = true
    }
}
