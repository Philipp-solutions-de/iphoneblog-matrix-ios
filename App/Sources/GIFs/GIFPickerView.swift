import MatrixRustSDK
import SwiftUI

/// A request from a composer's + menu: where the picked GIF goes is the composer's business.
struct GIFPickRequest: Identifiable {
    let id = UUID()
    let roomID: String
    let send: @MainActor (LibraryGIF) -> Void
}

/// The picker's state: one list at a time (Beliebt or Neu, or a search across both), paged.
@MainActor
final class GIFPickerModel: ObservableObject {
    enum State: Equatable { case loading, ready, notMember, failed }

    @Published var sort: GIFSort = .popular { didSet { if sort != oldValue { reload() } } }
    @Published var query = "" { didSet { if query != oldValue { reload(after: .milliseconds(300)) } } }
    @Published private(set) var gifs: [LibraryGIF] = []
    @Published private(set) var state: State = .loading
    @Published private(set) var thumbnails: [String: UIImage] = [:]
    @Published var notice: String?

    private let api: GIFLibraryAPI
    private let client: Client
    private var next: String?
    private var loading: Task<Void, Never>?

    init(session: ChatSession) {
        api = GIFLibraryAPI(session: session)
        client = session.client
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func reload(after delay: Duration = .zero) {
        loading?.cancel()
        loading = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            state = gifs.isEmpty ? .loading : state
            await load(from: nil)
        }
    }

    /// The next page when the last tile shows.
    func reached(_ gif: LibraryGIF) {
        guard gif.id == gifs.last?.id, let next, loading == nil || loading?.isCancelled == true else { return }
        loading = Task { await load(from: next) }
    }

    private func load(from: String?) async {
        defer { loading = nil }
        do {
            let page = try await api.list(sort: sort, query: query, from: from)
            guard !Task.isCancelled else { return }
            gifs = from == nil ? page.gifs : gifs + page.gifs.filter { new in !gifs.contains { $0.id == new.id } }
            next = page.next
            state = .ready
        } catch GIFLibraryError.notMember {
            state = .notMember
        } catch {
            if !Task.isCancelled, from == nil { state = .failed }
        }
    }

    /// A still frame for a tile, from the server's thumbnail of the GIF.
    func thumbnail(for gif: LibraryGIF) async {
        guard thumbnails[gif.id] == nil, let source = try? MediaSource.fromUrl(url: gif.mxc),
              let data = try? await client.getMediaThumbnail(mediaSource: source, width: 240, height: 240),
              let image = UIImage(data: data) else { return }
        thumbnails[gif.id] = image
    }

    /// "Schlagworte bearbeiten": the GIF's tags replaced by these (comma-separated).
    func setTags(_ text: String, of gif: LibraryGIF) async {
        switch GIFTags.parse(text) {
        case .failure(.badTag(let why)):
            notice = why
        case .failure:
            notice = "Die Schlagworte ließen sich nicht speichern."
        case .success(let tags):
            do {
                let stored = try await api.replaceTags(tags, of: gif.id)
                if let index = gifs.firstIndex(of: gif) { gifs[index].tags = stored }
            } catch GIFLibraryError.badTag(let why) {
                notice = why
            } catch GIFLibraryError.tooMany {
                notice = "Zu viele Änderungen in kurzer Zeit. Später nochmal."
            } catch {
                notice = "Die Schlagworte ließen sich nicht speichern."
            }
        }
    }

    /// "Melden": the GIF leaves the grid at once (the server takes it out of the picker).
    func report(_ gif: LibraryGIF) async {
        gifs.removeAll { $0.id == gif.id }
        do {
            try await api.report(gif.id)
        } catch GIFLibraryError.tooMany {
            notice = "Zu viele Meldungen in kurzer Zeit. Später nochmal."
        } catch {
            notice = "Die Meldung ging nicht raus."
        }
    }
}

/// "GIFs aus dem Chat" (gif-library.md, "Web reference", adapted to iOS): Beliebt and Neu, a
/// search, three tiles a row. A tap sends at once; a long press offers "Schlagworte bearbeiten"
/// and "Melden".
struct GIFPickerView: View {
    @StateObject private var model: GIFPickerModel
    let send: (LibraryGIF) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: LibraryGIF?
    @State private var tagText = ""
    @State private var reporting: LibraryGIF?

    init(session: ChatSession, send: @escaping (LibraryGIF) -> Void) {
        _model = StateObject(wrappedValue: GIFPickerModel(session: session))
        self.send = send
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.gifs) { gif in
                        tile(gif)
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, 8)
            }
            .overlay { emptyState }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.isSearching {
                    Picker("Liste", selection: $model.sort) {
                        ForEach(GIFSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.bottom, 6)
                    .background(Theme.background)
                    .accessibilityIdentifier("gif-picker.sort")
                }
            }
            .background(Theme.background)
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "GIFs durchsuchen")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("GIFs aus dem Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Schlagworte bearbeiten", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("z. B. jubeln, facepalm", text: $tagText)
                    .textInputAutocapitalization(.never)
                Button("Speichern") {
                    if let gif = editing { Task { await model.setTags(tagText, of: gif) } }
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Durch Kommas getrennt. Jedes Mitglied kann Schlagworte ergänzen oder korrigieren.")
            }
            .confirmationDialog("GIF melden? Es verschwindet sofort aus der Auswahl.",
                                isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                                titleVisibility: .visible) {
                Button("Melden", role: .destructive) {
                    if let gif = reporting { Task { await model.report(gif) } }
                }
                Button("Abbrechen", role: .cancel) { }
            }
            .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("OK", role: .cancel) { }
            }
        }
        .task { model.reload() }
    }

    private func tile(_ gif: LibraryGIF) -> some View {
        Button {
            send(gif)
            dismiss()
        } label: {
            ZStack {
                Theme.surface
                if let image = model.thumbnails[gif.id] {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if gif.needsTags {
                    Text("#?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                tagText = gif.tags.joined(separator: ", ")
                editing = gif
            } label: { Label("Schlagworte bearbeiten", systemImage: "tag") }
            Button(role: .destructive) {
                reporting = gif
            } label: { Label("Melden", systemImage: "flag") }
        }
        .accessibilityLabel(gif.tags.isEmpty ? "GIF ohne Schlagworte" : "GIF: " + gif.tags.joined(separator: ", "))
        .accessibilityIdentifier("gif-picker.tile")
        .task { await model.thumbnail(for: gif) }
        .onAppear { model.reached(gif) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.gifs.isEmpty {
            switch model.state {
            case .loading:
                ProgressView()
            case .ready:
                ContentUnavailableView(model.isSearching ? "Nichts gefunden" : "Noch keine GIFs", systemImage: "sparkles.rectangle.stack",
                                       description: Text(model.isSearching ? "Vielleicht hat das GIF noch kein Schlagwort." : "GIFs, die in #one gepostet werden, landen hier."))
            case .notMember:
                ContentUnavailableView("Nur für #one-Mitglieder", systemImage: "lock")
            case .failed:
                ContentUnavailableView {
                    Label("Nicht erreichbar", systemImage: "wifi.slash")
                } actions: {
                    Button("Nochmal versuchen") { model.reload() }.tint(Theme.teal)
                }
            }
        }
    }
}
