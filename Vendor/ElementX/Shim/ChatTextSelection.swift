//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// "Text auswählen" in a message's menu (Thorsten, 2026-11-17, from Alex's screenshot): the
// message's text in a sheet, selectable but not editable, so part of it can be copied. iOS's own
// selection handles and "Kopieren" do the rest. TimelineInteractionHandler (patch) calls it.

import SwiftUI
import UIKit

@MainActor
enum ChatTextSelection {
    static func present(text: String) {
        let controller = UIHostingController(rootView: TextSelectionSheet(text: text))
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }
}

private struct TextSelectionSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    private var style: ChatKitStyle { ChatKitStyle.current }

    var body: some View {
        NavigationStack {
            SelectableText(text: text, color: UIColor(style.colors.ink))
                .padding(.horizontal, 16)
                .navigationTitle("Text auswählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .accessibilityIdentifier("text-selection.done")
                    }
                }
        }
    }
}

/// A UITextView, because SwiftUI's `textSelection(.enabled)` copies only the whole text on iOS.
private struct SelectableText: UIViewRepresentable {
    let text: String
    let color: UIColor

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        view.accessibilityIdentifier = "text-selection.text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.text = text
        view.textColor = color
    }
}
