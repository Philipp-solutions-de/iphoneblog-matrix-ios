import QuickLook
import UIKit

/// "Markieren" for a picked photo (Thorsten, 2026-11-19): Apple's own Markup in Quick Look, on
/// the iPhone. The person draws, writes or highlights, taps Fertig, and the marked-up copy
/// replaces the photo in the upload preview; it is sent like any photo. Nothing leaves the phone
/// before Senden.
@MainActor
enum ChatMarkup {
    /// Presents Quick Look with editing on, over whatever is on top. `done` gets the edited
    /// picture, or nil when the person closed without saving.
    static func present(imageURL: URL, done: @escaping (UIImage?) -> Void) {
        guard let top = topViewController() else { done(nil); return }
        // Quick Look edits a copy; ours lives beside the original, never the original itself.
        let copy = imageURL.deletingLastPathComponent()
            .appendingPathComponent("markup-\(UUID().uuidString).\(imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension)")
        do {
            try FileManager.default.copyItem(at: imageURL, to: copy)
        } catch {
            done(nil)
            return
        }
        let controller = MarkupController(url: copy, done: done)
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class MarkupController: QLPreviewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private let url: URL
    private let done: (UIImage?) -> Void
    private var edited: UIImage?

    init(url: URL, done: @escaping (UIImage?) -> Void) {
        self.url = url
        self.done = done
        super.init(nibName: nil, bundle: nil)
        dataSource = self
        delegate = self
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }

    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        .createCopy
    }

    func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
        edited = UIImage(contentsOfFile: modifiedContentsURL.path)
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        try? FileManager.default.removeItem(at: url)
        done(edited)
    }
}
