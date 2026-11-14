//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI
import WysiwygComposer

typealias GenericKeyHandler = (_ key: UIKeyboardHIDUsage) -> Void
typealias PasteHandler = ([NSItemProvider]) -> Void

struct MessageComposer: View {
    @Binding var plainComposerText: NSAttributedString
    @Binding var presendCallback: (() -> Void)?
    @Binding var selectedRange: NSRange
    
    let composerView: WysiwygComposerView
    let mode: ComposerMode
    let placeholder: String
    
    let composerFormattingEnabled: Bool
    let showResizeGrabber: Bool
    @Binding var isExpanded: Bool
    
    let sendAction: () -> Void
    let editAction: () -> Void
    let pasteAction: PasteHandler
    let cancellationAction: () -> Void
    let onAppearAction: () -> Void
    
    @State private var composerTranslation: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if showResizeGrabber {
                resizeGrabber
            }
            
            composerTextField
                .messageComposerStyle(header: header)
                // Explicitly disable all animations to fix weirdness with the header immediately
                // appearing whilst the text field and keyboard are still animating up to it.
                .animation(.noAnimation, value: mode)
        }
        .gesture(showResizeGrabber ? dragGesture : nil)
    }
    
    // MARK: - Private
    
    @State private var composerFrame = CGRect.zero
    
    @ViewBuilder
    private var composerTextField: some View {
        if composerFormattingEnabled {
            Color.clear
                .overlay(alignment: .top) {
                    composerView
                        .clipped()
                        .readFrame($composerFrame)
                }
                .frame(minHeight: ComposerConstant.minHeight, maxHeight: max(composerHeight, composerFrame.height),
                       alignment: .top)
                .onAppear {
                    onAppearAction()
                }
        } else {
            MessageComposerTextField(placeholder: placeholder,
                                     text: $plainComposerText,
                                     presendCallback: $presendCallback,
                                     selectedRange: $selectedRange,
                                     maxHeight: ComposerConstant.maxHeight,
                                     keyHandler: { handleKeyPress($0) },
                                     pasteHandler: pasteAction)
        }
    }
    
    private var composerHeight: CGFloat {
        let baseHeight = isExpanded ? ComposerConstant.maxHeight : ComposerConstant.minHeight
        return (baseHeight - composerTranslation).clamped(to: ComposerConstant.allowedHeightRange)
    }
    
    @ViewBuilder
    private var header: some View {
        switch mode {
        case .reply(_, let replyDetails, _):
            MessageComposerReplyHeader(replyDetails: replyDetails, action: cancellationAction)
        case .edit(_, let editType):
            MessageComposerEditHeader(editType: editType, action: cancellationAction)
        case .recordVoiceMessage, .previewVoiceMessage, .default:
            EmptyView()
        }
    }
    
    private var resizeGrabber: some View {
        Capsule()
            .foregroundStyle(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                composerTranslation += value.translation.height
            }
            .onEnded { _ in
                withElementAnimation(.easeIn(duration: 0.3)) {
                    if composerTranslation > ComposerConstant.translationThreshold {
                        isExpanded = false
                    } else if composerTranslation < -ComposerConstant.translationThreshold {
                        isExpanded = true
                    }
                    composerTranslation = 0
                }
            }
    }
    
    private func handleKeyPress(_ key: UIKeyboardHIDUsage) {
        switch key {
        case .keyboardReturnOrEnter:
            sendAction()
        case .keyboardUpArrow:
            editAction()
        case .keyboardEscape:
            cancellationAction()
        default:
            break
        }
    }
}

struct MessageComposerReplyHeader: View {
    let replyDetails: TimelineItemReplyDetails
    let action: () -> Void
    
    var body: some View {
        TimelineReplyView(placement: .composer, timelineItemReplyDetails: replyDetails, maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                Button(action: action) {
                    CompoundIcon(\.close, size: .small, relativeTo: .compound.bodySMSemibold)
                        .foregroundColor(.compound.iconTertiary)
                        .padding(4.0)
                }
                .accessibilityLabel(L10n.actionClose)
            }
            .padding(.vertical, 8.0)
            .padding(.horizontal, -4.0)
    }
}

private struct MessageComposerEditHeader: View {
    let editType: ComposerMode.EditType
    let action: () -> Void
    
    private var title: String {
        switch editType {
        case .default: L10n.commonEditing
        case .addCaption: L10n.commonAddingCaption
        case .editCaption: L10n.commonEditingCaption
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Label(title, icon: \.editSolid, iconSize: .xSmall, relativeTo: .compound.bodySMSemibold)
                .labelStyle(MessageComposerHeaderLabelStyle())
            Spacer()
            Button(action: action) {
                CompoundIcon(\.close, size: .small, relativeTo: .compound.bodySMSemibold)
                    .foregroundColor(.compound.iconTertiary)
                    .padding([.leading, .vertical], 6.0)
            }
            .accessibilityLabel(L10n.actionClose)
        }
    }
}

private struct MessageComposerHeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 4) {
            configuration.icon
            configuration.title
        }
        .font(.compound.bodySMSemibold)
        .foregroundColor(.compound.textSecondary)
        .lineLimit(1)
    }
}

// MARK: - Style

extension View {
    /// - Parameter contentIncludesPadding: Pass `true` for content that already insets itself within the composer shape.
    func messageComposerStyle(header: some View = EmptyView(), contentIncludesPadding: Bool = false) -> some View {
        modifier(MessageComposerStyleModifier(header: header, contentIncludesPadding: contentIncludesPadding))
    }
}

private struct MessageComposerStyleModifier<Header: View>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    
    let header: Header
    let contentIncludesPadding: Bool
    
    private let composerShape = RoundedRectangle(cornerRadius: 21, style: .circular)
    private let horizontalPadding: CGFloat = Compound.supportsGlass ? 16 : 12
    
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isEnabled {
                mainContent(content: content)
                    .snapshotableGlassEffect(.regular.interactive(), // Doesn't need to be interactive but Apple does it 🤷‍♂️
                                             snapshotBackground: .compound.bgSubtleSecondary,
                                             in: composerShape)
            } else {
                mainContent(content: content)
                    .background(.compound.bgSubtlePrimary, in: composerShape)
            }
        } else {
            mainContent(content: content)
                .background {
                    ZStack {
                        composerShape
                            .fill(Color.compound.bgSubtleSecondary)
                        composerShape
                            .stroke(Color.compound.borderInteractiveSecondary, lineWidth: 0.5)
                    }
                }
        }
    }
    
    func mainContent(content: Content) -> some View {
        VStack(alignment: .leading, spacing: contentIncludesPadding ? 0 : -6) {
            header
                .padding(.horizontal, horizontalPadding)
            
            content
                .tint(.compound.iconAccentTertiary)
                .padding(.vertical, contentIncludesPadding ? 0 : (Compound.supportsGlass ? 11 : 10))
                .padding(.horizontal, contentIncludesPadding ? 0 : horizontalPadding)
        }
        .clipShape(composerShape)
    }
}

// MARK: - Previews
