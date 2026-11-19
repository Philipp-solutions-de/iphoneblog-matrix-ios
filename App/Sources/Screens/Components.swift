import SafariServices
import SwiftUI

/// Initials on a colour that stays the same for the same name, in the avatar squircle.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = Theme.Size.avatar

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let index = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Theme.avatarColors.count
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.37, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.avatarColors[index], in: AvatarShape.of(size))
            .accessibilityHidden(true)
    }
}

/// The large title at the top of a tab ("@Mentions", "Ich").
struct ScreenTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.screenTitle)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, 6)
            .padding(.bottom, 8)
    }
}

/// Small capitals above a group ("MITTEILUNGEN", "KONTO").
struct GroupHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.overline)
            .tracking(0.4)
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, Theme.Space.page + 14)
            .padding(.top, 22)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rounded group of settings rows with hairlines between them.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content()) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 {
                        Divider().overlay(Theme.line).padding(.leading, 16)
                    }
                }
            }
        }
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.Size.groupCorner))
        .padding(.horizontal, Theme.Space.page)
    }
}

/// One settings row: label left, value or accessory right, at least 48 pt tall.
struct SettingsRow<Accessory: View>: View {
    let label: String
    var labelColor: Color = Theme.ink
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(labelColor)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(label: String, labelColor: Color = Theme.ink) {
        self.init(label: label, labelColor: labelColor) { EmptyView() }
    }
}

/// A row that opens a page: label and a chevron or an arrow out.
struct LinkRow: View {
    let label: String
    var external = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(label: label) {
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .buttonStyle(.plain)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// In-app Safari for the account, privacy and #one pages.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.teal)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) { }
}

extension Bundle {
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
