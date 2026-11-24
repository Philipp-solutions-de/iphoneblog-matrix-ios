import Foundation
import MatrixRustSDK

/// "GIFs aus dem Chat": GIFs members already posted in #one, picked from the app's library
/// (gif-library.md; App/Sources/GIFs). ChatKit adds the + menu entry where the app offers it and
/// sends the picked GIF by its mxc, without uploading it again.
@MainActor
public enum ChatGIFLibrary {
    /// Set by the app: whether a room's composer offers the library (#one rooms and their
    /// threads, never the Blog room).
    public static var isOffered: (String) -> Bool = { _ in false }

    static let menuTitle = "GIFs aus dem Chat"

    /// The message for a picked GIF: an m.image with the library's mxc, its size and
    /// `image/gif`, as gif-library.md asks; no upload.
    static func content(for gif: ChatGIF) throws -> RoomMessageEventContentWithoutRelation {
        let info = ImageInfo(height: gif.height.map(UInt64.init), width: gif.width.map(UInt64.init),
                             mimetype: "image/gif", size: gif.size.map(UInt64.init),
                             thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: true)
        let image = ImageMessageContent(filename: gif.filename, caption: nil, formattedCaption: nil,
                                        source: try MediaSource.fromUrl(url: gif.mxc), info: info)
        return try messageEventContentNew(msgtype: .image(content: image))
    }

    /// Sends a picked GIF on the screen's timeline: a room's, or a thread's into the thread.
    static func send(_ gif: ChatGIF, on controller: TimelineControllerProtocol, host: ChatKitHost?) {
        Task { @MainActor in
            guard let controller = controller as? TimelineController,
                  let content = try? content(for: gif),
                  case .success = await controller.sendMessageEventContent(content) else {
                host?.showMessage("Das GIF ließ sich nicht senden.")
                return
            }
        }
    }
}

/// A GIF from the library, ready to send.
public struct ChatGIF: Sendable, Equatable {
    public let mxc: String
    public let width: Int?
    public let height: Int?
    public let size: Int?
    public let filename: String

    public init(mxc: String, width: Int?, height: Int?, size: Int?, filename: String = "gif.gif") {
        self.mxc = mxc
        self.width = width
        self.height = height
        self.size = size
        self.filename = filename
    }
}
