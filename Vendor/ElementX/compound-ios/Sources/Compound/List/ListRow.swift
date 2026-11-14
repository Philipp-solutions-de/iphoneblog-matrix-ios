//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

public enum ListRowColor {
    public static var separatorTint: Color {
        if #available(iOS 26, *) {
            .compound.bgSubtleSecondary
        } else {
            .compound._borderInteractiveSecondaryAlpha
        }
    }
}

public enum ListRowPadding {
    public static let horizontal: CGFloat = 16
    public static let vertical: CGFloat = 13
    public static let insets = EdgeInsets(top: vertical,
                                          leading: horizontal,
                                          bottom: vertical,
                                          trailing: horizontal)
    
    public static let textFieldInsets = EdgeInsets(top: 11,
                                                   leading: horizontal,
                                                   bottom: 11,
                                                   trailing: horizontal)
    
    public static let labelIconSpacing: CGFloat = Compound.supportsGlass ? 12 : 16
}

public struct ListRow<Icon: View, DetailsIcon: View, CustomContent: View, SelectionValue: Hashable>: View {
    @Environment(\.isEnabled) private var isEnabled
    
    let label: ListRowLabel<Icon>
    let details: ListRowDetails<DetailsIcon>?
    
    public enum Kind<CustomView: View, Selection: Hashable> {
        case label
        case button(action: () -> Void)
        case navigationLink(action: () -> Void)
        case picker(selection: Binding<Selection>, items: [(title: String, tag: Selection)])
        case toggle(Binding<Bool>)
        case inlinePicker(selection: Binding<Selection>, items: [(title: String, tag: Selection)])
        case selection(isSelected: Bool, action: () -> Void)
        case multiSelection(isSelected: Bool, action: () -> Void)
        case textField(text: Binding<String>, axis: Axis?)
        case secureField(text: Binding<String>)
        
        case custom(@MainActor () -> CustomView)
        
        public static func textField(text: Binding<String>) -> Self {
            .textField(text: text, axis: nil)
        }
    }
    
    let kind: Kind<CustomContent, SelectionValue>
    
    public var body: some View {
        rowContent
            .buttonStyle(ListRowButtonStyle())
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.compound.bgCanvasDefaultLevel1)
            .listRowSeparatorTint(ListRowColor.separatorTint)
    }
    
    @ViewBuilder
    var rowContent: some View {
        switch kind {
        case .label:
            RowContent(details: details) { label }
        case .button(let action):
            Button(action: action) {
                RowContent(details: details) { label }
            }
        case .navigationLink(let action):
            Button(action: action) {
                RowContent(details: details, accessory: .navigationLink) { label }
            }
        case .picker(let selection, let items):
            HStack(spacing: 0) {
                label
                Spacer()
                // Note: VoiceOver label already provided.
                Picker("", selection: selection) {
                    ForEach(items, id: \.tag) { item in
                        Text(item.title)
                            .tag(item.tag)
                    }
                }
                .labelsHidden()
                .padding(.vertical, -10)
                .padding(.trailing, ListRowPadding.horizontal)
            }
            .accessibilityElement(children: .combine)
        case .toggle(let binding):
            HStack(spacing: 0) {
                label
                Spacer()
                HStack(spacing: ListRowTrailingSectionSpacing.horizontal) {
                    if let details {
                        ListRowTrailingSection(details)
                    }
                    
                    // Note: VoiceOver label already provided.
                    Toggle("", isOn: binding)
                        .toggleStyle(.compound)
                        .labelsHidden()
                        .padding(.vertical, -10)
                }
            }
            .padding(.trailing, ListRowPadding.horizontal)
            .accessibilityElement(children: .combine)
        case .inlinePicker(let selection, let items):
            ListInlinePicker(title: label.title ?? "",
                             selection: selection,
                             items: items,
                             isWaiting: details?.isWaiting ?? false)
        case .selection(let isSelected, let action):
            Button(action: action) {
                RowContent(details: details, accessory: .selection(isSelected)) { label }
            }
            .accessibilityAddTraits(.isToggle)
        case .multiSelection(let isSelected, let action):
            Button(action: action) {
                RowContent(details: details, accessory: .multiSelection(isSelected)) { label }
            }
            .accessibilityAddTraits(.isToggle)
        case .textField(let text, let axis):
            TextField(text: text, axis: axis) {
                Text(label.title ?? "")
                    .compoundTextFieldPlaceholder()
            }
            .tint(.compound.iconAccentTertiary)
            .foregroundStyle(isEnabled ? .compound.textPrimary : .compound.textDisabled)
            .listRowInsets(ListRowPadding.textFieldInsets)
            // The title is used as the placeholder, which VoiceOver only reads while empty.
            .accessibilityLabel(label.title ?? "")
        case .secureField(let text):
            SecureField(text: text) {
                Text(label.title ?? "")
                    .compoundTextFieldPlaceholder()
            }
            .tint(.compound.iconAccentTertiary)
            .foregroundStyle(isEnabled ? .compound.textPrimary : .compound.textDisabled)
            .listRowInsets(ListRowPadding.textFieldInsets)
            .accessibilityLabel(label.title ?? "")
            
        case .custom(let content):
            content()
        }
    }
}

// MARK: - Initialisers

/// Normal row with a details icon
public extension ListRow where CustomContent == EmptyView {
    init(label: ListRowLabel<Icon>,
         details: ListRowDetails<DetailsIcon>? = nil,
         kind: Kind<CustomContent, SelectionValue>) {
        self.label = label
        self.details = details
        self.kind = kind
    }
    
    init(label: ListRowLabel<Icon>,
         details: ListRowDetails<DetailsIcon>? = nil,
         kind: Kind<CustomContent, SelectionValue>) where SelectionValue == String {
        self.label = label
        self.details = details
        self.kind = kind
    }
}

/// Normal row without a details icon.
public extension ListRow where DetailsIcon == EmptyView, CustomContent == EmptyView {
    init(label: ListRowLabel<Icon>,
         details: ListRowDetails<DetailsIcon>? = nil,
         kind: Kind<CustomContent, SelectionValue>) {
        self.label = label
        self.details = details
        self.kind = kind
    }
    
    init(label: ListRowLabel<Icon>,
         details: ListRowDetails<DetailsIcon>? = nil,
         kind: Kind<CustomContent, SelectionValue>) where SelectionValue == String {
        self.label = label
        self.details = details
        self.kind = kind
    }
}

/// Custom row without a label or details label.
public extension ListRow where Icon == EmptyView, DetailsIcon == EmptyView {
    init(kind: Kind<CustomContent, SelectionValue>) {
        label = ListRowLabel()
        details = nil
        self.kind = kind
    }
    
    init(kind: Kind<CustomContent, SelectionValue>) where SelectionValue == String {
        label = ListRowLabel()
        details = nil
        self.kind = kind
    }
}

/// The standard content for labels, and button based rows.
///
/// This doesn't use `LabeledContent` as that will happily build using an `EmptyView`
/// in the content. This creates an issue where the label ends up hidden to VoiceOver,
/// presumably because SwiftUI thinks that the row doesn't contain any content.
private struct RowContent<Label: View, DetailsIcon: View>: View {
    let details: ListRowDetails<DetailsIcon>?
    var accessory: ListRowAccessory?
    let label: () -> Label
    
    var body: some View {
        // If not custom, the label() content usually includes a leading `ListRowPadding.horizontal`
        // that's why the external `HStack` has 0 spacing.
        HStack(spacing: 0) {
            // We should always have multi selection shown on the leading side
            if let accessory, accessory.kind.isMultiSelection {
                accessory
                    .padding(.leading, ListRowPadding.horizontal)
            }
            
            HStack(spacing: ListRowTrailingSectionSpacing.horizontal) {
                label()
                    .frame(maxWidth: .infinity)
                
                if details != nil || accessory != nil {
                    ListRowTrailingSection(details,
                                           // Prevent multi selection to appear on the trailing side
                                           accessory: accessory?.kind.isMultiSelection == true ? nil : accessory)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.trailing, ListRowPadding.horizontal)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Helpers

private extension TextField {
    /// Creates a text field with an optional preferred axis. Hard coding a default resulted
    /// in the underlying component always being a `UITextView` during introspection.
    /// This initialiser does the right thing when not supplying an axis in `ListRow.Kind`.
    init(text: Binding<String>, axis: Axis?, label: () -> Label) {
        if let axis {
            self.init(text: text, axis: axis, label: label)
        } else {
            self.init(text: text, label: label)
        }
    }
}

// MARK: - Previews

// swiftlint:disable print_deprecation

// swiftlint:enable print_deprecation
