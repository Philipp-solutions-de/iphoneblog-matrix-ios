import SwiftUI
import UIKit

/// The share sheet: what goes out on top, a line to write something, the #one rooms to pick
/// from, and "Senden". Everything here is #one, so the tint is the #one red (Theme: #EB686E,
/// #C4434A where it carries white text or must read on white).
struct ShareView: View {
    @ObservedObject var model: ShareModel

    static let tint = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xEB / 255, green: 0x68 / 255, blue: 0x6E / 255, alpha: 1)
        : UIColor(red: 0xC4 / 255, green: 0x43 / 255, blue: 0x4A / 255, alpha: 1) })

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Teilen in #one")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { model.cancel() }
                            .accessibilityIdentifier("share.cancel")
                    }
                    if model.state == .ready || model.state == .sending {
                        ToolbarItem(placement: .confirmationAction) {
                            if model.state == .sending {
                                ProgressView()
                            } else {
                                Button("Senden") { Task { await model.send() } }
                                    .bold()
                                    .disabled(!model.canSend)
                                    .accessibilityIdentifier("share.send")
                            }
                        }
                    }
                }
        }
        .tint(Self.tint)
        .alert("Nicht gesendet", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.failure ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .signedOut:
            ContentUnavailableView("Nicht angemeldet", systemImage: "person.crop.circle",
                                   description: Text("Melde dich in der \(Brand.appName)-App an, dann kannst du in #one teilen."))
        case .noRooms:
            ContentUnavailableView("Kein #one-Raum", systemImage: "number",
                                   description: Text("Teilen geht in die Räume von #one. Öffne die \(Brand.appName)-App einmal, dann stehen sie hier."))
        case .ready, .sending:
            form
        }
    }

    private var form: some View {
        Form {
            if !model.images.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.images) { image in
                                Image(uiImage: image.preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityLabel("Bild")
                            }
                        }
                    }
                } footer: {
                    if model.skipped > 0 {
                        Text(model.skipped == 1 ? "Ein Bild lässt sich nicht lesen und bleibt weg." : "\(model.skipped) Bilder lassen sich nicht lesen und bleiben weg.")
                    }
                }
            }
            if let link = model.link {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = model.linkTitle {
                            Text(title).font(.body.weight(.semibold)).lineLimit(2)
                        }
                        Label(link.host() ?? link.absoluteString, systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("share.link")
                }
            }
            Section {
                TextField(model.images.isEmpty ? "Nachricht" : "Bildunterschrift", text: $model.words, axis: .vertical)
                    .lineLimit(3...10)
                    .accessibilityIdentifier("share.words")
            }
            Section("Raum") {
                ForEach(model.rooms) { room in
                    Button {
                        model.roomID = room.id
                    } label: {
                        HStack {
                            Text(room.name).foregroundStyle(.primary)
                            Spacer()
                            if model.roomID == room.id {
                                Image(systemName: "checkmark").foregroundStyle(Self.tint).bold()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("share.room")
                    .accessibilityAddTraits(model.roomID == room.id ? .isSelected : [])
                }
            }
        }
        .disabled(model.state == .sending)
    }
}
