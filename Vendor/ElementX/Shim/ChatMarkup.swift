import PencilKit
import UIKit

/// "Markieren" for a picked photo (Thorsten, 2026-11-19): draw, write or highlight on the photo
/// with PencilKit. Fertig puts the marked-up copy in place of the photo in the
/// upload preview, and it is sent like any photo. Nothing leaves the phone before Senden.
///
/// PencilKit, not Quick Look's Markup (approved 2026-11-20): Quick Look hides its Markup button
/// behind controls that come and go, which no test could rely on, and it edits files, not pictures.
@MainActor
enum ChatMarkup {
    /// Presents the editor over whatever is on top. `done` gets the marked-up picture, or nil
    /// when the person cancels.
    static func present(imageURL: URL, done: @escaping (UIImage?) -> Void) {
        guard let top = topViewController(), let image = UIImage(contentsOfFile: imageURL.path) else {
            done(nil)
            return
        }
        let editor = MarkupViewController(image: image, done: done)
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .fullScreen
        top.present(navigation, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The photo with a PencilKit canvas laid exactly over it, and Apple's tool picker below.
private final class MarkupViewController: UIViewController, PKCanvasViewDelegate {
    private let image: UIImage
    private let done: (UIImage?) -> Void
    private let imageView = UIImageView()
    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var finished = false
    private static let pen = PKInkingTool(.pen, color: UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1), width: 6)

    init(image: UIImage, done: @escaping (UIImage?) -> Void) {
        self.image = image
        self.done = done
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Markieren"

        imageView.image = image
        imageView.contentMode = .scaleToFill
        view.addSubview(imageView)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // A finger draws; without this only an Apple Pencil would, and the iPhone has none.
        canvas.drawingPolicy = .anyInput
        // Ink shows as drawn: in dark mode PencilKit would turn dark ink light, and the picture
        // is sent as it looks here.
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = self
        canvas.accessibilityIdentifier = "markup.canvas"
        view.addSubview(canvas)

        let cancel = UIBarButtonItem(title: "Abbrechen", style: .plain, target: self, action: #selector(cancelTapped))
        cancel.accessibilityIdentifier = "markup.cancel"
        let finish = UIBarButtonItem(title: "Fertig", style: .done, target: self, action: #selector(doneTapped))
        finish.accessibilityIdentifier = "markup.done"
        // Fertig only once something is drawn: an untouched photo needs no copy.
        finish.isEnabled = false
        navigationItem.leftBarButtonItem = cancel
        navigationItem.rightBarButtonItem = finish

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = .white
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The picker hands its selected tool to the canvas; red stands out on most photos.
        toolPicker.selectedTool = Self.pen
        toolPicker.overrideUserInterfaceStyle = .light
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The photo fitted into the safe area; the canvas covers exactly the photo, so a
        // stroke's place on screen is its place on the picture.
        let area = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 8, dy: 8)
        let size = image.size
        guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else { return }
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        let frame = CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2,
                           width: fitted.width, height: fitted.height)
        if imageView.frame != frame {
            imageView.frame = frame
            canvas.frame = frame
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        navigationItem.rightBarButtonItem?.isEnabled = !canvasView.drawing.strokes.isEmpty
    }

    @objc private func cancelTapped() { finish(with: nil) }

    @objc private func doneTapped() { finish(with: rendered()) }

    /// The photo at its own pixel size with the drawing scaled onto it.
    private func rendered() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let shown = canvas.bounds
        var drawing = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            drawing = canvas.drawing.image(from: shown, scale: shown.width > 0 ? size.width / shown.width : 1)
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            drawing.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func finish(with result: UIImage?) {
        guard !finished else { return }
        finished = true
        toolPicker.setVisible(false, forFirstResponder: canvas)
        toolPicker.removeObserver(canvas)
        dismiss(animated: true) { [done] in done(result) }
    }
}
