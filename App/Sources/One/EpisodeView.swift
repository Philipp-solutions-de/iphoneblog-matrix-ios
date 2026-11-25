import SwiftUI

/// One episode (spec-ios.md "Episode page"): the player inline at the top, the poster until it
/// plays; then title, date, duration and the show notes. "Im Chat besprechen" waits for an
/// episode's chat thread, which does not exist yet (open item in the spec).
struct EpisodeView: View {
    let episode: Episode
    @ObservedObject var player: EpisodePlayer
    let close: () -> Void

    var body: some View {
        EpisodePage(episode: episode, player: player)
            .onDisappear(perform: close)
    }
}

/// The page itself, observing the player it is handed.
private struct EpisodePage: View {
    let episode: Episode
    @ObservedObject var player: EpisodePlayer
    @ObservedObject private var progress = PlaybackProgress.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    // Only once it plays: a UIKit view under the poster would take its tap.
                    if player.started {
                        EpisodePlayerView(model: player)
                    } else {
                        Button { player.play() } label: {
                            EpisodePoster(episode: episode, entry: progress.entry(episode.videoID), showsNew: false, corner: 0)
                                .overlay {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 64, height: 64)
                                        .background(.black.opacity(0.55), in: Circle())
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(resumeLabel)
                        .accessibilityIdentifier("episode.play")
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)

                controls

                VStack(alignment: .leading, spacing: 8) {
                    Text((["Video", episode.numberLabel, episode.dateLabel] as [String?]).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.coralText)
                    Text(episode.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("episode.title")
                    HStack(spacing: 6) {
                        if player.duration > 0 { Text(Episode.duration(player.duration)) }
                        if let status = progress.label(episode.videoID) {
                            Text("·")
                            Text(status).foregroundStyle(status.hasPrefix("Weiter") ? Theme.teal : Theme.ink3)
                                .accessibilityIdentifier("episode.status")
                        }
                    }
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.ink3)
                    if let notes = ShowNotes.text(episode.notesHTML) {
                        Text(notes)
                            .font(Theme.Font.reading)
                            .foregroundStyle(Theme.ink2)
                            .tint(Theme.teal)
                            .padding(.top, 6)
                            .accessibilityIdentifier("episode.notes")
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .navigationTitle(episode.numberLabel ?? "Folge")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resumeLabel: String {
        if let entry = progress.entry(episode.videoID), entry.started { return "Weiter ab \(Episode.duration(entry.position))" }
        return "Ansehen"
    }

    /// ±10 s, speed and captions under the picture (spec-ios.md "Player").
    private var controls: some View {
        HStack(spacing: 0) {
            control("gobackward.10", "10 Sekunden zurück", "player.back") { player.skip(-10) }
            Spacer()
            Button { player.nextSpeed() } label: {
                Text(EpisodePlayer.speedLabel(player.speed))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 52, minHeight: 44)
            }
            .accessibilityLabel("Geschwindigkeit \(EpisodePlayer.speedLabel(player.speed))")
            .accessibilityIdentifier("player.speed")
            Spacer()
            if player.hasCaptions {
                CaptionsButton(player: player)
                Spacer()
            }
            control("goforward.10", "10 Sekunden vor", "player.forward") { player.skip(10) }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func control(_ icon: String, _ label: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).frame(minWidth: 52, minHeight: 44)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// The feed item's description: HTML to text with links (spec "Episode page"). Its own small
/// parser: NSAttributedString's HTML import runs WebKit in a nested run loop, which inside a
/// SwiftUI body stopped the page from redrawing. Paragraphs, line breaks, list items as bullets,
/// links, bold and italic; every other tag is dropped.
enum ShowNotes {
    static func text(_ html: String?) -> AttributedString? {
        guard let html, !html.isEmpty else { return nil }
        var result = AttributedString()
        var bold = 0, italic = 0
        var link: URL?
        var pendingBreak = false
        func append(_ raw: String) {
            let text = decode(raw.replacingOccurrences(of: "\n", with: " "))
            guard !text.isEmpty else { return }
            if pendingBreak, !result.characters.isEmpty { result.append(AttributedString("\n")) }
            pendingBreak = false
            var piece = AttributedString(text)
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link { piece.link = link }
            result.append(piece)
        }
        var rest = Substring(html)
        while let open = rest.firstIndex(of: "<") {
            append(String(rest[..<open]))
            guard let close = rest[open...].firstIndex(of: ">") else { rest = rest[open...]; break }
            let tag = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            let name = tag.lowercased().split(whereSeparator: { $0 == " " || $0 == "/" }).first.map(String.init) ?? ""
            let closing = tag.hasPrefix("/")
            switch (name, closing) {
            case ("p", _), ("br", _), ("div", _), ("ul", _), ("ol", _): pendingBreak = true
            case ("li", false):
                pendingBreak = true
                append("• ")
            case ("li", true): pendingBreak = true
            case ("strong", false), ("b", false): bold += 1
            case ("strong", true), ("b", true): bold = max(0, bold - 1)
            case ("em", false), ("i", false): italic += 1
            case ("em", true), ("i", true): italic = max(0, italic - 1)
            case ("a", false): link = href(tag).flatMap(URL.init(string:))
            case ("a", true): link = nil
            default: break
            }
            rest = rest[rest.index(after: close)...]
        }
        append(String(rest))
        return result.characters.isEmpty ? nil : result
    }

    private static func href(_ tag: String) -> String? {
        guard let range = tag.range(of: #"href\s*=\s*"([^"]*)""#, options: .regularExpression) else { return nil }
        let match = tag[range]
        guard let first = match.firstIndex(of: "\""), let last = match.lastIndex(of: "\""), first < last else { return nil }
        return decode(String(match[match.index(after: first)..<last]))
    }

    private static func decode(_ text: String) -> String {
        var out = text
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#8211;", "–"), ("&#8217;", "’"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
    }
}

/// "CC": the captions on or off, in the episode page and under an article card's video; the
/// web chat's button says the same (Thorsten's word, 2026-11-21).
struct CaptionsButton: View {
    @ObservedObject var player: EpisodePlayer

    var body: some View {
        Button { player.captionsOn.toggle() } label: {
            Text("CC")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(player.captionsOn ? Theme.background : Theme.ink2)
                .background(player.captionsOn ? Theme.ink2 : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.ink2, lineWidth: 1.5))
                .frame(minWidth: 52, minHeight: 44)
        }
        .accessibilityLabel(player.captionsOn ? "Untertitel aus" : "Untertitel an")
        .accessibilityIdentifier("player.captions")
    }
}
