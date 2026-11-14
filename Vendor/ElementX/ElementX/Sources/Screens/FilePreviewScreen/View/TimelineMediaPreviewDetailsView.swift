//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI
import UniformTypeIdentifiers

struct TimelineMediaPreviewDetailsView: View {
    let item: TimelineMediaPreviewItem.Media
    @ObservedObject var context: TimelineMediaPreviewViewModel.Context
    var preferredColorScheme: ColorScheme? = .dark
    @Binding var sheetHeight: CGFloat
    
    /// Approximate height of the navigation bar.
    private let topPadding: CGFloat = 72
    
    var body: some View {
        ElementNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    details
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { sheetHeight = $0 + topPadding }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(L10n.screenMediaDetailsTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.compound.bgCanvasDefault)
        .presentationColorScheme(preferredColorScheme)
        .sheet(item: $context.redactConfirmationItem) { item in
            TimelineMediaPreviewRedactConfirmationView(item: item,
                                                       context: context,
                                                       preferredColorScheme: preferredColorScheme)
        }
    }
    
    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsRow(title: L10n.screenMediaDetailsUploadedBy) {
                HStack(spacing: 12) {
                    LoadableAvatarImage(url: item.sender.avatarURL,
                                        name: item.sender.displayName,
                                        contentID: item.sender.id,
                                        avatarSize: .user(on: .mediaPreviewDetails),
                                        mediaProvider: context.mediaProvider)
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let displayName = item.sender.displayName {
                            Text(displayName)
                                .font(.compound.bodyLGSemibold)
                                .foregroundStyle(.compound.decorativeColor(for: item.sender.id).text)
                        }
                        
                        Text(item.sender.id)
                            .font(.compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                    }
                }
            }
            
            DetailsRow(title: L10n.screenMediaDetailsUploadedOn) {
                Text(item.timestamp.formatted(date: .long, time: .shortened))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
            }
            
            DetailsRow(title: L10n.screenMediaDetailsFilename) {
                Text(item.filename ?? "")
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
            }
            
            if let contentType = item.contentType {
                DetailsRow(title: L10n.screenMediaDetailsFileFormat) {
                    Group {
                        if let fileSize = item.fileSize {
                            Text(contentType) + Text(" • ") + Text(UInt(fileSize).formatted(.byteCount(style: .file)))
                        } else {
                            Text(contentType)
                        }
                    }
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
                }
            }
        }
        .padding(.bottom, 32)
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var actions: some View {
        if let actions = context.viewState.currentItemActions {
            VStack(spacing: 0) {
                if !actions.actions.isEmpty {
                    Divider()
                        .background(Color.compound.bgSubtlePrimary)
                }
                
                ForEach(actions.actions, id: \.self) { action in
                    ActionButton(item: item, action: action, context: context)
                }
                
                if !actions.secondaryActions.isEmpty {
                    Divider()
                        .background(Color.compound.bgSubtlePrimary)
                }
                
                ForEach(actions.secondaryActions, id: \.self) { action in
                    ActionButton(item: item, action: action, context: context)
                }
            }
        }
    }
    
    private struct DetailsRow<Content: View>: View {
        let title: String
        let content: () -> Content
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Compound.supportsGlass ? .compound.bodyMDSemibold : .compound.bodyXS)
                    .foregroundStyle(.compound.textSecondary)
                    .textCase(Compound.supportsGlass ? nil : .uppercase)
                
                content()
            }
        }
    }
    
    private struct ActionButton: View {
        let item: TimelineMediaPreviewItem.Media
        let action: TimelineItemMenuAction
        let context: TimelineMediaPreviewViewModel.Context
        
        var body: some View {
            if action == .downloadMedia {
                if item.fileHandle?.url != nil {
                    button
                }
            } else {
                button
            }
        }
        
        var button: some View {
            Button(role: action.isDestructive ? .destructive : nil) {
                context.send(viewAction: .menuAction(action, item: item))
            } label: {
                action.label
            }
            .buttonStyle(.menuSheet)
        }
    }
}

// MARK: - Previews
