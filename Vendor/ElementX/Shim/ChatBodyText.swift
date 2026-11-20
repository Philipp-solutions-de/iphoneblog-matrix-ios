//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The text a message's formatted body shows in the timeline, for tests (BodyTextTests): the
/// same AttributedStringBuilder the timeline uses, without the attributes.
public enum ChatBodyText {
    public static func shown(html: String) -> String? {
        let builder = AttributedStringBuilder(cacheKey: "bodyTextTests", mentionBuilder: PlainMentionBuilder())
        return builder.fromHTML(html).map { String($0.characters) }
    }
}
