import SwiftUI
import UIKit

/// The app in the share sheet: web pages, links, text and pictures go into a #one room the
/// member picks (Thorsten, 2026-11-26). The sheet is SwiftUI (ShareView); this controller
/// only hosts it and ends the extension's request.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(items: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
        model.finish = { [weak self] sent in
            if sent {
                self?.extensionContext?.completeRequest(returningItems: nil)
            } else {
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        }
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}
