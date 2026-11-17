//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// The room and thread screens behind ChatKitSession.roomView and threadView. They assemble
// Element X's timeline and composer view models as its room and thread coordinators do, and
// present the sheets those screens ask for (emoji picker, photo picker, upload preview).
// Everything Element X routes to its app (calls, polls, location, forwarding, reports) is
// either left out or handed to the app's ChatKitHost.

import Combine
import Compound
import MatrixRustSDK
import SwiftUI
import WysiwygComposer

// MARK: - Presenting sheets and notices

/// One screen's sheets and its toasts and spinners (Element X's user indicators).
@MainActor
final class ChatScreenPresenter: ObservableObject {
    struct Sheet: Identifiable {
        let id = UUID()
        let coordinator: CoordinatorProtocol
        let view: AnyView
    }

    /// The sheet on screen. A sheet that leaves, closed, swiped away or replaced by the next one
    /// (the photo picker by the upload preview), stops its own coordinator here. Stopping in the
    /// sheet's onDismiss stopped the wrong one: by then `sheet` already held the next screen,
    /// and the upload preview's preparation was cancelled before Senden could use it.
    @Published var sheet: Sheet? {
        didSet {
            if let oldValue, oldValue.id != sheet?.id { oldValue.coordinator.stop() }
        }
    }
    let userIndicatorController = UserIndicatorController()

    /// `inNavigation` gives screens with a toolbar (the upload preview's Abbrechen) the
    /// navigation bar Element X's navigation stack would.
    func present(_ coordinator: CoordinatorProtocol, inNavigation: Bool = false) {
        coordinator.start()
        let view = coordinator.toPresentable()
        sheet = Sheet(coordinator: coordinator, view: inNavigation ? AnyView(NavigationStack { view }) : view)
    }

    func dismiss() {
        sheet = nil
    }
}

/// A screen ChatKit builds asynchronously: the room proxy and timeline load first.
@MainActor
protocol ChatScreenCoordinator: AnyObject {
    func start()
    func stop()
    func toPresentable() -> AnyView
}

/// Shows a spinner while the screen loads, then the screen with its sheets and notices.
struct ChatScreenLoader: View {
    let id: String
    let make: @MainActor (ChatScreenPresenter) async throws -> ChatScreenCoordinator

    @StateObject private var presenter = ChatScreenPresenter()
    @StateObject private var holder = CoordinatorHolder()
    @State private var failure: String?

    var body: some View {
        Group {
            if let coordinator = holder.coordinator {
                coordinator.toPresentable()
            } else if let failure {
                ContentUnavailableView(L10n.commonError, systemImage: "exclamationmark.bubble",
                                       description: Text(failure))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.compound.bgCanvasDefault)
            }
        }
        .task(id: id) {
            guard holder.coordinator == nil else { return }
            do {
                let coordinator = try await make(presenter)
                coordinator.start()
                holder.coordinator = coordinator
            } catch {
                MXLog.error("ChatKit could not open \(id): \(error)")
                #if DEBUG
                failure = "\(L10n.errorUnknown)\n\(error)"
                #else
                failure = L10n.errorUnknown
                #endif
            }
        }
        .sheet(item: $presenter.sheet) { sheet in
            // The sheet covers the screen, so its spinners and errors (preparing an upload,
            // a failed one) show on top of it, as Element X's window-wide indicators do.
            sheet.view.overlay {
                UserIndicatorPresenter(userIndicatorController: presenter.userIndicatorController)
                    .allowsHitTesting(presenter.userIndicatorController.activeIndicator?.type == .modal)
            }
        }
        .overlay {
            UserIndicatorPresenter(userIndicatorController: presenter.userIndicatorController)
                .allowsHitTesting(presenter.userIndicatorController.activeIndicator?.type == .modal)
        }
    }
}

/// Keeps a screen's coordinator alive for as long as SwiftUI keeps the view's state, and stops it
/// after (which saves the composer's draft).
@MainActor
private final class CoordinatorHolder: ObservableObject {
    @Published var coordinator: ChatScreenCoordinator?

    isolated deinit {
        coordinator?.stop()
    }
}

// MARK: - Sheets both screens open

/// The sheets the timeline asks for, shared by the room and thread screens.
@MainActor
private struct ChatSheets {
    let session: ChatKitSession
    let presenter: ChatScreenPresenter
    let timelineController: TimelineControllerProtocol

    func emojiPicker(selectedEmojis: Set<String>, continuation: EmojiPickerScreenContinuation) {
        let coordinator = EmojiPickerScreenCoordinator(parameters: .init(mode: .reaction,
                                                                         selectedEmojis: selectedEmojis,
                                                                         emojiProvider: session.emojiProvider,
                                                                         continuation: continuation))
        var cancellable: AnyCancellable?
        cancellable = coordinator.actions.sink { [presenter] action in
            switch action {
            case .dismiss:
                presenter.dismiss()
                cancellable?.cancel()
            }
        }
        presenter.present(coordinator)
    }

    func mediaPicker(source: MediaPickerScreenSource, caption: NSAttributedString) {
        let mode = MediaPickerScreenMode(source: source, selectionType: .multiple(galleryEnabled: false))
        let coordinator = MediaPickerScreenCoordinator(mode: mode,
                                                       userIndicatorController: presenter.userIndicatorController,
                                                       orientationManager: ChatOrientationManager()) { [self] action in
            switch action {
            case .selectedMediaAtURLs(let urls):
                uploadPreview(mediaURLs: urls, caption: caption)
            case .cancel:
                presenter.dismiss()
            }
        }
        presenter.present(coordinator)
    }

    func uploadPreview(mediaURLs: [URL], caption: NSAttributedString?) {
        let parameters = MediaUploadPreviewScreenCoordinatorParameters(mediaURLs: mediaURLs,
                                                                        caption: caption,
                                                                        title: nil,
                                                                        shouldShowCaptionWarning: false,
                                                                        galleryEnabled: false,
                                                                        mediaUploadingPreprocessor: MediaUploadingPreprocessor(userSettings: session.userSession.userSettings),
                                                                        timelineController: timelineController,
                                                                        clientProxy: session.clientProxy,
                                                                        userIndicatorController: presenter.userIndicatorController)
        let coordinator = MediaUploadPreviewScreenCoordinator(parameters: parameters)
        var cancellable: AnyCancellable?
        cancellable = coordinator.actions.sink { [presenter] action in
            switch action {
            case .dismiss:
                presenter.dismiss()
                cancellable?.cancel()
            }
        }
        presenter.present(coordinator, inNavigation: true)
    }
}

// MARK: - Room

/// "Show this message in its room": set by a search result, taken by that room's screen when it
/// is (or becomes) live. Element X's own focus then loads the message in context.
@MainActor
final class ChatFocusRequests: ObservableObject {
    struct Request: Equatable { let roomID: String; let eventID: String }
    static let shared = ChatFocusRequests()
    @Published var pending: Request?
}


/// A channel or direct message. Element X's room coordinator, without the room screen view
/// model's calls, pinned messages, knock requests and identity warnings.
@MainActor
final class ChatRoomCoordinator: ChatScreenCoordinator {
    private let session: ChatKitSession
    private let roomProxy: JoinedRoomProxyProtocol
    private weak var host: ChatKitHost?
    private let screenViewModel: ThreadTimelineScreenViewModel
    private let timelineViewModel: TimelineViewModel
    private let composerViewModel: ComposerToolbarViewModel
    private let sheets: ChatSheets
    private var cancellables = Set<AnyCancellable>()

    init(session: ChatKitSession, roomProxy: JoinedRoomProxyProtocol, presenter: ChatScreenPresenter, host: ChatKitHost) {
        self.session = session
        self.roomProxy = roomProxy
        self.host = host

        let itemFactory = session.timelineItemFactory()
        let timelineController = session.timelineControllerFactory.buildTimelineController(roomProxy: roomProxy,
                                                                                            initialFocussedEventID: nil,
                                                                                            timelineItemFactory: itemFactory,
                                                                                            mediaProvider: session.userSession.mediaProvider)
        sheets = ChatSheets(session: session, presenter: presenter, timelineController: timelineController)

        // The thread screen's view model holds what a conversation screen needs: title, avatar,
        // whether the reader may write, the media preview. It is not specific to threads.
        screenViewModel = ThreadTimelineScreenViewModel(roomProxy: roomProxy, userSession: session.userSession)

        timelineViewModel = TimelineViewModel(roomProxy: roomProxy,
                                              focussedEventID: nil,
                                              timelineController: timelineController,
                                              userSession: session.userSession,
                                              mediaPlayerProvider: session.mediaPlayerProvider,
                                              userIndicatorController: presenter.userIndicatorController,
                                              appMediator: session.appMediator(host: host),
                                              analyticsService: session.analytics,
                                              emojiProvider: session.emojiProvider,
                                              linkMetadataProvider: session.linkMetadataProvider,
                                              timelineControllerFactory: session.timelineControllerFactory)

        composerViewModel = ChatComposer.make(roomProxy: roomProxy, threadRootEventID: nil, session: session,
                                              itemFactory: itemFactory, timelineContext: timelineViewModel.context)
    }

    func start() {
        timelineViewModel.actions
            .sink { [weak self] action in self?.handle(action) }
            .store(in: &cancellables)

        composerViewModel.actions
            .sink { [weak self] action in self?.timelineViewModel.process(composerAction: action) }
            .store(in: &cancellables)

        composerViewModel.start()

        // A search result asked to show a message here (ChatKitSession.focus).
        ChatFocusRequests.shared.$pending
            .compactMap { [roomID = roomProxy.id] in $0?.roomID == roomID ? $0 : nil }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                ChatFocusRequests.shared.pending = nil
                self?.timelineViewModel.context.send(viewAction: .focusOnEventID(request.eventID))
            }
            .store(in: &cancellables)
    }

    func stop() {
        composerViewModel.stop()
        screenViewModel.stop()
    }

    func toPresentable() -> AnyView {
        let info = roomProxy.infoPublisher.value
        let title = info.isDirect ? info.displayNameOrID : ChatKitStrings.channel(info.displayNameOrID)
        return AnyView(ChatRoomScreen(context: screenViewModel.context,
                                      timelineContext: timelineViewModel.context,
                                      unread: info.unreadMessagesCount,
                                      composerToolbar: ComposerToolbar(context: composerViewModel.context),
                                      title: title,
                                      // The room's topic if it has one; no member count, which is the same
                                      // everywhere (Thorsten).
                                      subtitle: info.topic.flatMap { $0.isEmpty ? nil : $0 })
            .environment(\.chatComposerPlaceholder, ChatKitStrings.messageTo(title))
            .environment(\.chatShowsEncryptionNote, info.isDirect))
    }

    private func handle(_ action: TimelineViewModelAction) {
        switch action {
        case .displayThread(let itemID):
            guard let eventID = itemID.eventID else { return }
            host?.openThread(roomID: roomProxy.id, rootEventID: eventID)
        case .displayEmojiPicker(let selectedEmojis, let continuation):
            sheets.emojiPicker(selectedEmojis: selectedEmojis, continuation: continuation)
        case .displayCameraPicker:
            sheets.mediaPicker(source: .camera, caption: composerViewModel.context.plainComposerText)
        case .displayMediaPicker:
            sheets.mediaPicker(source: .photoLibrary, caption: composerViewModel.context.plainComposerText)
        case .displayDocumentPicker:
            sheets.mediaPicker(source: .documents(), caption: composerViewModel.context.plainComposerText)
        case .displayMediaUploadPreviewScreen(let mediaURLs):
            sheets.uploadPreview(mediaURLs: mediaURLs, caption: composerViewModel.context.plainComposerText)
        case .displayMediaPreview(let mediaPreviewViewModel):
            screenViewModel.displayMediaPreview(mediaPreviewViewModel)
        case .displaySenderDetails(let userID):
            host?.openUser(userID: userID)
        case .displayRoom(let roomID, _):
            host?.openRoom(roomID: roomID)
        case .composer(let action):
            composerViewModel.process(timelineAction: action)
        case .displayReportContent(let itemID, _):
            if let eventID = itemID.eventID {
                host?.reportMessage(roomID: roomProxy.id, eventID: eventID)
            }
        default:
            // Calls, polls, location, forwarding and the pinned timeline are not part of our app.
            break
        }
    }
}

/// The room screen: Element X's thread screen layout with the room's name as its title.
private struct ChatRoomScreen: View {
    @ObservedObject var context: ThreadTimelineScreenViewModelType.Context
    @ObservedObject var timelineContext: TimelineViewModelType.Context
    /// Unread when the room opened, for the jump pill ("137 neue · zur ersten springen").
    let unread: UInt
    let composerToolbar: ComposerToolbar
    let title: String
    let subtitle: String?

    private var style: ChatKitStyle { ChatKitStyle.current }

    var body: some View {
        TimelineView(timelineContext: timelineContext)
            .background(.compound.bgCanvasDefault)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title)
                            .font(style.fonts.roomTitle)
                            .foregroundStyle(style.colors.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(style.fonts.roomSubtitle)
                                .foregroundStyle(style.colors.ink3)
                        }
                    }
                    .lineLimit(1)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(style.colors.background, for: .navigationBar)
            .timelineMediaPreview(viewModel: $context.mediaPreviewViewModel)
            .overlay(alignment: .top) {
                if timelineContext.viewState.shouldShowJumpToReadMarker {
                    // The web's pill (v0.6.5): the first unread message is above, out of sight.
                    Button { timelineContext.send(viewAction: .scrollToReadMarker) } label: {
                        Label(ChatKitStrings.jumpToUnread(unread), systemImage: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(style.colors.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .accessibilityLabel(ChatKitStrings.jumpToUnread(unread))
                    .accessibilityIdentifier("room.jumpToUnread")
                } else {
                    FloatingDateBadge(dateText: timelineContext.floatingDate?.formattedDateSeparator()) {
                        timelineContext.send(viewAction: .scrollToFirstItemForCurrentDate)
                    }
                    .padding(.top, 13)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                TimelineScrollButton(isHidden: !timelineContext.viewState.shouldShowScrollToBottomButton) {
                    timelineContext.send(viewAction: .scrollToBottom)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if context.viewState.canSendMessage {
                        composerToolbar
                    } else {
                        ComposerDisabledView()
                    }
                }
                .padding(.top, 8)
                .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
                .environmentObject(timelineContext)
                .environment(\.timelineContext, timelineContext)
                .environment(\.shouldAutomaticallyLoadImages, !timelineContext.viewState.hideTimelineMedia)
            }
    }
}

// MARK: - Thread

/// One thread: Element X's thread coordinator as it is, with its sheets handled here.
@MainActor
final class ChatThreadCoordinator: ChatScreenCoordinator {
    private let coordinator: ThreadTimelineScreenCoordinator
    private let sheets: ChatSheets
    private let roomID: String
    private let rootEventID: String
    private weak var host: ChatKitHost?
    private var cancellables = Set<AnyCancellable>()

    init(session: ChatKitSession, roomProxy: JoinedRoomProxyProtocol, rootEventID: String,
         presenter: ChatScreenPresenter, host: ChatKitHost) async throws {
        self.host = host
        roomID = roomProxy.id
        self.rootEventID = rootEventID
        let itemFactory = session.timelineItemFactory()
        let result = await session.timelineControllerFactory.buildThreadTimelineController(threadRootEventID: rootEventID,
                                                                                            initialFocussedEventID: nil,
                                                                                            roomProxy: roomProxy,
                                                                                            timelineItemFactory: itemFactory,
                                                                                            mediaProvider: session.userSession.mediaProvider)
        guard case let .success(timelineController) = result else { throw ChatKitError.threadUnavailable }
        sheets = ChatSheets(session: session, presenter: presenter, timelineController: timelineController)

        let parameters = ThreadTimelineScreenCoordinatorParameters(userSession: session.userSession,
                                                                   roomProxy: roomProxy,
                                                                   focussedEventID: nil,
                                                                   timelineController: timelineController,
                                                                   mediaPlayerProvider: session.mediaPlayerProvider,
                                                                   emojiProvider: session.emojiProvider,
                                                                   linkMetadataProvider: session.linkMetadataProvider,
                                                                   completionSuggestionService: CompletionSuggestionService(roomProxy: roomProxy,
                                                                                                                            roomListPublisher: Just([]).eraseToAnyPublisher()),
                                                                   appMediator: session.appMediator(host: host),
                                                                   analytics: session.analytics,
                                                                   composerDraftService: ComposerDraftService(roomProxy: roomProxy,
                                                                                                              timelineItemfactory: itemFactory,
                                                                                                              threadRootEventID: rootEventID),
                                                                   timelineControllerFactory: session.timelineControllerFactory,
                                                                   userIndicatorController: presenter.userIndicatorController)
        coordinator = ThreadTimelineScreenCoordinator(parameters: parameters)
    }

    func start() {
        ChatThreadActivity.shared.markSeen(roomID: roomID, rootEventID: rootEventID)
        coordinator.actions
            .sink { [weak self] action in self?.handle(action) }
            .store(in: &cancellables)
        coordinator.start()
    }

    func stop() {
        // Replies read while the thread was open count as seen.
        ChatThreadActivity.shared.markSeen(roomID: roomID, rootEventID: rootEventID)
        coordinator.stop()
    }

    func toPresentable() -> AnyView {
        AnyView(coordinator.toPresentable()
            .environment(\.chatComposerPlaceholder, ChatKitStrings.replyPlaceholder))
    }

    private func handle(_ action: ThreadTimelineScreenCoordinatorAction) {
        switch action {
        case .presentEmojiPicker(let selectedEmojis, let continuation):
            sheets.emojiPicker(selectedEmojis: selectedEmojis, continuation: continuation)
        case .presentMediaUploadPicker(let mode, let caption):
            sheets.mediaPicker(source: mode.source, caption: caption)
        case .presentMediaUploadPreviewScreen(let mediaURLs, let caption):
            sheets.uploadPreview(mediaURLs: mediaURLs, caption: caption)
        case .presentRoomMemberDetails(let userID):
            host?.openUser(userID: userID)
        case .presentReportContent(let itemID, _):
            if let eventID = itemID.eventID {
                host?.reportMessage(roomID: roomID, eventID: eventID)
            }
        default:
            break
        }
    }
}

// MARK: - Composer

/// Element X's composer: markdown in plain-text mode, its formatting toolbar behind + ›
/// Textformatierung, mentions and replies.
@MainActor
enum ChatComposer {
    static func make(roomProxy: JoinedRoomProxyProtocol, threadRootEventID: String?, session: ChatKitSession,
                     itemFactory: RoomTimelineItemFactoryProtocol, timelineContext: TimelineViewModel.Context) -> ComposerToolbarViewModel {
        let wysiwygViewModel = WysiwygComposerViewModel(minHeight: ComposerConstant.minHeight,
                                                        maxCompressedHeight: ComposerConstant.maxHeight,
                                                        maxExpandedHeight: ComposerConstant.maxHeight,
                                                        parserStyle: .elementX)
        return ComposerToolbarViewModel(initialText: nil,
                                        roomProxy: roomProxy,
                                        wysiwygViewModel: wysiwygViewModel,
                                        completionSuggestionService: CompletionSuggestionService(roomProxy: roomProxy,
                                                                                                 roomListPublisher: Just([]).eraseToAnyPublisher()),
                                        mediaProvider: session.userSession.mediaProvider,
                                        mentionDisplayHelper: ComposerMentionDisplayHelper(timelineContext: timelineContext),
                                        userSettings: session.userSession.userSettings,
                                        analyticsService: session.analytics,
                                        composerDraftService: ComposerDraftService(roomProxy: roomProxy,
                                                                                   timelineItemfactory: itemFactory,
                                                                                   threadRootEventID: threadRootEventID))
    }
}

// MARK: - Our own strings

/// Texts ChatKit adds to Element X's. German, like the rest of the app.
enum ChatKitStrings {

    /// "Noch keine Antworten", "1 Antwort", "5 Antworten".
    /// "137 neue · zur ersten springen"; without a count, "Neue Nachrichten · zur ersten springen".
    static func jumpToUnread(_ count: UInt) -> String {
        count > 0 ? "\(count > 999 ? "999+" : "\(count)") neue · zur ersten springen" : "Neue Nachrichten · zur ersten springen"
    }

    static func replies(_ count: Int) -> String {
        count == 0 ? "Noch keine Antworten" : count == 1 ? "1 Antwort" : "\(count) Antworten"
    }

    /// Composer placeholder in a channel and in a thread.
    static func messageTo(_ roomName: String) -> String { "Nachricht an \(roomName)" }

    /// A channel's name with one "#": "# Fotos", and "#one-Chat" as it is (it carries its own).
    static func channel(_ name: String) -> String { name.hasPrefix("#") ? name : "# \(name)" }
    static let replyPlaceholder = "Antworten…"
    static let unread = "ungelesen"

    /// "Letzte Antwort vor 5 Min.", "Letzte Antwort gerade eben".
    static func lastReply(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 { return "Letzte Antwort gerade eben" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return "Letzte Antwort " + formatter.localizedString(for: date, relativeTo: now)
    }

    /// The Threads row at the top of #one-Chat.
    static let threadsTitle = "Threads"

    /// Under a photo, video or file while it uploads.
    static let uploading = "Wird hochgeladen"

    /// The Threads tab when it is empty.
    static let noThreadsTitle = "Noch keine Threads"
    static let noThreadsText = "Wenn du in einem Thread schreibst oder einen beginnst, steht er hier."

}

extension EnvironmentValues {
    /// The composer's placeholder for this screen; nil keeps Element X's.
    @Entry var chatComposerPlaceholder: String?
    /// Whether the composer says the room is not end-to-end encrypted: in direct messages only.
    @Entry var chatShowsEncryptionNote = false
}
