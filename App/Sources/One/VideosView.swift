import SwiftUI

/// All episodes, newest first (spec-ios.md "Videos"): poster with duration and progress,
/// "Folge N", the title, and "Weiter ab m:ss", "Gesehen" or the date.
struct VideosView: View {
    @ObservedObject var episodes: EpisodesModel
    @ObservedObject var router: Router
    @ObservedObject private var progress = PlaybackProgress.shared

    var body: some View {
        List {
            ForEach(episodes.episodes) { episode in
                Button { router.chatPath.append(.episode(episode)) } label: {
                    VideoRow(episode: episode, entry: progress.entry(episode.videoID), status: progress.label(episode.videoID))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: Theme.Space.page, bottom: 8, trailing: Theme.Space.page))
                .listRowBackground(Theme.background)
                .accessibilityIdentifier("videos.row")
                .onAppear { if episode == episodes.episodes.last { Task { await episodes.loadMore() } } }
            }
        }
        .listStyle(.plain)
        .background(Theme.background)
        .scrollContentBackground(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Videos").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("Gewusst wie · \(max(episodes.total, episodes.episodes.count)) Folgen")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                        .accessibilityIdentifier("videos.subtitle")
                }
            }
        }
        .navigationTitle("Videos")
        .refreshable { await episodes.load() }
    }
}

private struct VideoRow: View {
    let episode: Episode
    let entry: PlaybackProgress.Entry?
    let status: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EpisodePoster(episode: episode, entry: entry, showsNew: false, corner: 8)
                .frame(width: 132)
                .overlay(alignment: .topTrailing) {
                    if entry?.finished == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, Theme.teal)
                            .padding(5)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                if let number = episode.numberLabel {
                    Text(number).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.coralText)
                }
                Text(episode.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(status ?? episode.dateLabel)
                    .font(.system(size: 13, weight: status?.hasPrefix("Weiter") == true ? .semibold : .regular))
                    .foregroundStyle(status?.hasPrefix("Weiter") == true ? Theme.teal : Theme.ink3)
                    .accessibilityIdentifier("videos.row.status")
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
