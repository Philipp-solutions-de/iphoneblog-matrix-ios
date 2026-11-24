import CryptoKit
import ImageIO
import SwiftUI
import Vision

/// The tag field for a GIF of one's own that is new to the library (gif-library.md, "Tag field
/// for a new GIF"): shown above the caption when the lookup by SHA-256 says `needs_tag`, with
/// suggestions from Apple's on-device image recognition. Nothing about the picture leaves the
/// phone; the tags go to the server after the GIF has gone out. Without a tag the GIF still goes
/// out, it just stays out of the picker.
@MainActor
final class ChatGIFTagModel: ObservableObject {
    @Published private(set) var needsTag = false
    @Published var text = ""
    @Published private(set) var suggestions: [String] = []
    private var sha256: String?

    /// Made with the upload preview's state, which is not on the main actor.
    nonisolated init() { }

    /// Looks up a single GIF in the draft; anything else shows no field.
    func prepare(_ urls: [URL]) {
        guard urls.count == 1, let url = urls.first, url.pathExtension.lowercased() == "gif",
              let data = try? Data(contentsOf: url) else { return }
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        sha256 = id
        Task {
            guard await ChatGIFLibrary.needsTags(id) else { return }
            needsTag = true
            suggestions = await Self.suggestions(for: data)
        }
    }

    /// nil when the field is empty or its tags are fine; else why not, before anything is sent.
    var problem: String? {
        guard needsTag, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ChatGIFLibrary.parseTags(text).problem
    }

    /// After the GIF went out: its tags to the library, if any.
    func submit() {
        guard needsTag, let sha256 else { return }
        let tags = ChatGIFLibrary.parseTags(text).tags
        guard !tags.isEmpty else { return }
        Task { await ChatGIFLibrary.addTags(sha256, tags) }
    }

    func add(_ suggestion: String) {
        let current = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !current.contains(where: { $0.lowercased() == suggestion }) else { return }
        text = (current + [suggestion]).joined(separator: ", ")
        suggestions.removeAll { $0 == suggestion }
    }

    /// Up to four labels Vision is fairly sure of, from the GIF's first frame, as tags the server
    /// would take (letters, at least three).
    nonisolated static func suggestions(for data: Data) async -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let request = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: frame).perform([request])) != nil else { return [] }
        return (request.results ?? [])
            .filter { $0.confidence >= 0.3 }
            .prefix(8)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ").lowercased() }
            .filter { $0.filter(\.isLetter).count >= 3 && $0.count <= 24 }
            .prefix(4)
            .map { $0 }
    }
}

/// "Schlagworte für die GIF-Auswahl": the chips, the field and the hint. Return sends.
struct ChatGIFTagField: View {
    @ObservedObject var model: ChatGIFTagModel
    let send: () -> Void

    var body: some View {
        if model.needsTag {
            VStack(alignment: .leading, spacing: 6) {
                Text("Schlagworte für die GIF-Auswahl")
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                if !model.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { model.add(suggestion) }
                                    .font(.compound.bodySM)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("gif-tags.suggestion")
                            }
                        }
                    }
                }
                TextField("z. B. jubeln, facepalm", text: $model.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemFill)))
                    .accessibilityIdentifier("gif-tags.field")
                Text(model.problem ?? "Ohne Schlagwort geht das GIF raus, aber nicht in die Auswahl.")
                    .font(.compound.bodyXS)
                    .foregroundStyle(model.problem == nil ? .compound.textSecondary : .compound.textCriticalPrimary)
            }
        }
    }
}
