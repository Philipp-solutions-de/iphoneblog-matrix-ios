//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct FileRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: FileRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            MediaFileRoomTimelineContent(filename: timelineItem.content.filename,
                                         fileSize: timelineItem.content.fileSize,
                                         caption: timelineItem.content.caption,
                                         formattedCaption: timelineItem.content.formattedCaption,
                                         trailingReservedSize: timelineItem.trailingReservedSize,
                                         shouldBoost: timelineItem.shouldBoost,
                                         contentScannerService: context?.contentScannerService,
                                         mediaSource: timelineItem.content.source,
                                         thumbnailSource: timelineItem.content.thumbnailSource) {
                context?.send(viewAction: .mediaTapped(itemID: timelineItem.id))
            }
            .accessibilityLabel(L10n.commonFile)
        }
    }
}

// MARK: Content

struct MediaFileRoomTimelineContent: View {
    let filename: String
    let fileSize: UInt?
    let caption: String?
    let formattedCaption: AttributedString?
    var trailingReservedSize: CGSize = .zero
    var shouldBoost = false
    var isAudioFile = false
    var contentScannerService: ContentScannerServiceProtocol?
    var mediaSource: MediaSourceProxy?
    var thumbnailSource: MediaSourceProxy?
    
    private var fileDescription: String {
        var fileDescription = "\(filename.validatedFileExtension.uppercased())"
        if let fileSize {
            fileDescription += " (\(fileSize.formatted(.byteCount(style: .file))))"
        }
        return fileDescription
    }
    
    var onMediaTap: (() -> Void)?
    
    private var icon: KeyPath<CompoundIcons, Image> {
        isAudioFile ? \.audio : \.attachment
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContentScanningView(contentScannerService: contentScannerService,
                                mediaSource: mediaSource,
                                thumbnailSource: thumbnailSource) {
                if let onMediaTap {
                    filePreview(isScanning: false)
                        .onTapGesture(perform: onMediaTap)
                } else {
                    filePreview(isScanning: false)
                }
            } scanningContent: {
                filePreview(isScanning: true)
            } unsafeContent: { failure in
                ContentScanningFailureView(failure: failure)
            }
            
            if let formattedCaption {
                FormattedBodyText(attributedString: formattedCaption,
                                  trailingReservedSize: trailingReservedSize,
                                  boostFontSize: shouldBoost)
            } else if let caption {
                FormattedBodyText(text: caption,
                                  trailingReservedSize: trailingReservedSize,
                                  boostFontSize: shouldBoost)
            }
        }
    }
    
    func filePreview(isScanning: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                Text(filename)
                    .foregroundStyle(.compound.textPrimary)
                    .font(.compound.bodyLG)
                Text(fileDescription)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
            .font(.compound.bodyLG)
            .foregroundStyle(.compound.textPrimary)
            .lineLimit(2)
        } icon: {
            FileTypeIconView(icon: icon, isScanning: isScanning)
        }
        .labelStyle(.custom(spacing: 8, alignment: .center))
        .padding(.horizontal, 4) // Add to the styler's padding of 8, as we use the default insets for the caption.
    }
}

/// The rounded icon badge used as the leading accessory of a file/audio row, either showing the
/// file-type icon or a scanning spinner.
struct FileTypeIconView: View {
    let icon: KeyPath<CompoundIcons, Image>
    var isScanning = false
    
    var body: some View {
        Group {
            if isScanning {
                ProgressView()
                    .scaledFrame(size: CompoundIcon.Size.medium.value, relativeTo: .compound.bodyLG)
            } else {
                CompoundIcon(icon)
                    .foregroundColor(.compound.iconPrimary)
            }
        }
        .scaledPadding(6)
        .background(.compound.iconOnSolidPrimary,
                    in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Previews
