import SwiftUI

/// The search over the blog and #one: a field that searches as you type, the filter chips with
/// their counts, one mixed list ranked by the server. Opened from the Blog tab and the #one hub
/// as a sheet; a tap closes it and opens the hit where it lives (MainView).
struct SiteSearchView: View {
    @ObservedObject var model: SiteSearchModel
    let open: (SiteSearchHit) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fieldActive = true

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.hits) { hit in
                    Button { open(hit) } label: { SiteSearchRow(hit: hit) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 12, leading: Theme.Space.page, bottom: 12, trailing: Theme.Space.page))
                        .listRowBackground(Theme.background)
                        .onAppear { if hit.id == model.hits.last?.id { model.loadMore() } }
                }
                if model.loadingMore {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                }
            }
            // A new filter starts its list at the top, not where the last one was scrolled to.
            .id(model.filter)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("site-search.list")
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SiteSearchChips(filter: $model.filter, counts: model.counts)
                }
            }
            .overlay { emptyState }
            .searchable(text: $model.query, isPresented: $fieldActive,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: model.signedIn ? "Blog und #one durchsuchen" : "Blog durchsuchen")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("site-search.done")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hits.isEmpty {
            switch model.state {
            case .searching:
                ProgressView().accessibilityIdentifier("site-search.loading")
            case .done:
                ContentUnavailableView("Keine Treffer", systemImage: "magnifyingglass",
                                       description: Text(model.filter == .all ? "Versuch ein anderes Wort." : "Unter „Alle“ gibt es vielleicht mehr."))
            case .failed(.rate):
                ContentUnavailableView("Zu viele Suchen auf einmal", systemImage: "hourglass",
                                       description: Text("Einen Moment warten, dann geht es weiter."))
            case .failed:
                ContentUnavailableView("Die Suche ist gerade nicht erreichbar", systemImage: "wifi.exclamationmark")
            case .idle:
                ContentUnavailableView(model.signedIn ? "Blog und #one durchsuchen" : "Blog durchsuchen", systemImage: "magnifyingglass",
                                       description: Text(model.signedIn
                                                         ? "Beiträge, Videos, Links und Chat."
                                                         : "Beiträge, Links und Diskussionen."))
            }
        }
    }
}

/// Alle · Beiträge · Videos · Links · Chat, each with its count from the server.
struct SiteSearchChips: View {
    @Binding var filter: SiteSearchFilter
    let counts: [String: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SiteSearchFilter.allCases) { chip($0) }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1 / 3) }
    }

    private func chip(_ option: SiteSearchFilter) -> some View {
        let selected = option == filter
        let count = option.count(in: counts)
        return Button { filter = option } label: {
            HStack(spacing: 5) {
                Text(option.title).font(.system(size: 14, weight: .semibold))
                if !counts.isEmpty {
                    Text(count > 99 ? "99+" : String(count))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .opacity(0.75)
                }
            }
            .foregroundStyle(selected ? .white : Theme.ink2)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(selected ? Theme.teal : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts.isEmpty ? option.title : "\(option.title), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("site-search.filter.\(option.rawValue)")
    }
}

/// One hit: the type badge, the title, the snippet with its marks, and who, where, when.
/// Everything it draws was prepared off the main thread (SiteSearchPage.prepare).
struct SiteSearchRow: View {
    let hit: SiteSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                SiteSearchBadge(kind: hit.kind, label: hit.label)
                if hit.locked {
                    Label("Nur für #one", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.coralText)
                        .labelStyle(.titleAndIcon)
                }
            }
            if !hit.title.characters.isEmpty {
                Text(hit.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            if !hit.snippet.characters.isEmpty {
                Text(hit.snippet)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(3)
            }
            if !hit.meta.isEmpty {
                Text(hit.meta)
                    .font(Theme.Font.time)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("site-search-hit")
    }
}

/// The kind of content: coral for #one only (the colour rule in Theme.swift), teal for the rest.
struct SiteSearchBadge: View {
    let kind: SiteSearchHit.Kind
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(label).font(Theme.Font.badge)
        }
        .foregroundStyle(kind == .one ? Theme.coralText : (kind == .link ? Theme.ink2 : Theme.teal))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(kind == .one ? Theme.coralSoft : (kind == .link ? Theme.surface : Theme.tealSoft), in: Capsule())
        .accessibilityLabel(label)
    }

    private var icon: String {
        switch kind {
        case .post: return "doc.text"
        case .one: return "number"
        case .video: return "play.fill"
        case .link: return "link"
        case .chat: return "bubble.left.and.bubble.right"
        case .discussion: return "text.bubble"
        }
    }
}
