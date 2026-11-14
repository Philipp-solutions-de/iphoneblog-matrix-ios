#!/usr/bin/env python3
# Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
#
# Remove SwiftUI previews from vendored Element X files, in place.
#
#   strip-previews.py <file.swift>...
#
# Element X's previews are built on its mocks (MediaProviderMock, JoinedRoomProxyMock, ...),
# which we do not vendor. scripts/sync-elementx.sh runs this on every copied Swift file
# before it applies patches/, so the removal never needs a hand-written patch.
#
# Removed, each with the doc comments and attributes directly above it:
# - `struct X_Previews: PreviewProvider ... { }` and `#Preview { }` blocks;
# - top-level `extension SomethingMock { }` blocks (extensions of generated mocks);
# - a top-level `extension ... { }` that directly follows a `// MARK: - Mocks` line, with that line;
# - a top-level `extension ... { }` whose first member is a `static func mock` or `static var mock`.

import re
import sys

START = re.compile(r'^[ \t]*(?:(?:private|fileprivate|internal|public|nonisolated|@MainActor)\s+)*'
                   r'(?:struct\s+\w+\s*:\s*[^{]*\bPreviewProvider\b[^{]*\{|#Preview\b[^{\n]*\{)'
                   r'|^extension\s+\w*Mock\b[^{]*\{'
                   r'|^// MARK: - Mocks[ \t]*\n(?:[ \t]*\n)*extension\b[^{]*\{'
                   r'|^(?:(?:private|fileprivate)\s+)?extension\b[^{\n]*\{'
                   r'(?=[ \t]*\n(?:[ \t]*\n)*[ \t]+static\s+(?:func|var|let)\s+mock)', re.M)


def block_end(text, open_brace):
    """Index just past the brace that closes the one at open_brace. Skips strings and comments."""
    depth, i, n = 0, open_brace, len(text)
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            i = text.find('\n', i)
            i = n if i < 0 else i
            continue
        if text.startswith('/*', i):
            i = text.find('*/', i + 2)
            i = n if i < 0 else i + 2
            continue
        if text.startswith('"""', i):
            i = text.find('"""', i + 3)
            i = n if i < 0 else i + 3
            continue
        if c == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == '\\' else 1
            i += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced braces')


def strip(text):
    out, pos = [], 0
    for m in START.finditer(text):
        if m.start() < pos:
            continue
        start = m.start()
        # Take attached doc comments and attributes with the block.
        lines_before = text[:start].split('\n')
        while len(lines_before) > 1 and re.match(r'^\s*(///|@)', lines_before[-2]):
            lines_before.pop(-2)
        start = len('\n'.join(lines_before[:-1])) + (1 if len(lines_before) > 1 else 0)
        end = block_end(text, m.end() - 1)
        if end < len(text) and text[end] == '\n':
            end += 1
        out.append(text[pos:start])
        pos = end
    out.append(text[pos:])
    result = ''.join(out)
    return re.sub(r'\n{3,}', '\n\n', result).rstrip() + '\n'


for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as f:
        original = f.read()
    stripped = strip(original)
    if stripped != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(stripped)
