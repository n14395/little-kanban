// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The app's own source, read off the disk this suite was compiled from.
///
/// Some claims are about the *text* of the code rather than about anything it
/// does at runtime — "no user-facing literal escapes the catalogue" is one, and
/// there is no value to inspect for it: a string that reached the screen without
/// going through `String(localized:)` looks exactly like one that did. The only
/// way to assert it is to read the source, so that is what this does.
///
/// `#filePath` is the absolute path of *this* file as the compiler saw it, and
/// `Tests/` sits beside `Sources/`. That makes the tree reachable from a test
/// run out of the same checkout and unreachable from anywhere else. Callers ask
/// `isReachable` first and say nothing rather than failing when the answer is
/// no: a test that cannot see the code it is describing has not found a problem.
enum SourceTree {
    /// Symlinks resolved on both sides, because the paths have to *match*: a
    /// checkout under `/tmp` is reached through a symlink, so `#filePath` says
    /// `/tmp/...` while the directory enumerator hands back `/private/tmp/...`.
    /// Left unresolved, every relative path came out absolute, every
    /// `hasPrefix("Store/")` filter matched nothing, and the tests that use one
    /// passed by scanning no files at all — which is why `files()` is checked
    /// to have found some.
    static let root = checkout.appending(path: "Sources")

    /// The checkout itself, for the handful of claims about files that are not
    /// Swift — the asset catalogue's `Contents.json` among them.
    static let checkout = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()

    static var isReachable: Bool {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        return !(contents ?? []).isEmpty
    }

    /// One entry per Swift file under `Sources/`, path relative to `Sources/`.
    static func files() -> [SourceFile] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        let prefix = root.path(percentEncoded: false) + "/"
        var found: [SourceFile] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let full = url.resolvingSymlinksInPath().path(percentEncoded: false)
            guard full.hasPrefix(prefix) else { continue }
            found.append(SourceFile(path: String(full.dropFirst(prefix.count)), text: text))
        }
        return found.sorted { $0.path < $1.path }
    }
}

/// One Swift file, with the small amount of lexing these assertions need.
///
/// Swift cannot be parsed with a regular expression and nothing here tries.
/// What it does is the one thing a regular expression cannot do and every check
/// needs: tell code from comments and from string literals, and find the end of
/// a call that starts on one line and finishes four lines later. Everything else
/// is matching on the result.
struct SourceFile {
    let path: String
    let text: String
    /// The file with every comment blanked out and newlines kept, so line
    /// numbers still hold. A rule about literals that counted the ones in doc
    /// comments would be a rule about prose.
    let code: [Character]

    init(path: String, text: String) {
        self.path = path
        self.text = text
        self.code = Self.masking(text)
    }

    private static func masking(_ text: String) -> [Character] {
        var out = Array(text)
        var i = 0
        var inString = false
        var escaped = false
        while i < out.count {
            let c = out[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; i += 1; continue }
            if c == "/", i + 1 < out.count, out[i + 1] == "/" {
                while i < out.count, out[i] != "\n" { out[i] = " "; i += 1 }
                continue
            }
            if c == "/", i + 1 < out.count, out[i + 1] == "*" {
                var depth = 0
                while i < out.count {
                    if out[i] == "/", i + 1 < out.count, out[i + 1] == "*" {
                        depth += 1
                        out[i] = " "; out[i + 1] = " "
                        i += 2
                        continue
                    }
                    if out[i] == "*", i + 1 < out.count, out[i + 1] == "/" {
                        depth -= 1
                        out[i] = " "; out[i + 1] = " "
                        i += 2
                        if depth <= 0 { break } else { continue }
                    }
                    if out[i] != "\n" { out[i] = " " }
                    i += 1
                }
                continue
            }
            i += 1
        }
        return out
    }

    var source: String { String(code) }

    func line(of offset: Int) -> Int {
        code[..<min(offset, code.count)].count { $0 == "\n" } + 1
    }

    /// The whole line an offset falls on. A type annotation — `let title:
    /// LocalizedStringResource = "Add Task"` — is what puts a bare literal into
    /// the catalogue without any call around it, and the annotation is on the
    /// same line as the literal.
    func line(containing offset: Int) -> String {
        let clamped = min(max(offset, 0), max(code.count - 1, 0))
        guard !code.isEmpty else { return "" }
        var start = clamped
        while start > 0, code[start - 1] != "\n" { start -= 1 }
        var end = clamped
        while end < code.count, code[end] != "\n" { end += 1 }
        return String(code[start..<end])
    }

    /// A call's text, from the head to its closing parenthesis — parentheses
    /// balanced, and ones inside string literals ignored, so an argument that
    /// contains a bracket does not cut the call short.
    ///
    /// `pattern` matches the head, e.g. `#"String\(\s*localized:"#`.
    func calls(headed pattern: String) -> [(offset: Int, text: String)] {
        guard let regex = try? Regex<AnyRegexOutput>(pattern) else { return [] }
        let whole = source
        var found: [(Int, String)] = []
        for match in whole.matches(of: regex) {
            let start = whole.distance(from: whole.startIndex, to: match.range.lowerBound)
            guard var i = code[start...].firstIndex(of: "(") else { continue }
            var depth = 0
            var inString = false
            var escaped = false
            while i < code.count {
                let c = code[i]
                if inString {
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { inString = false }
                } else if c == "\"" {
                    inString = true
                } else if c == "(" {
                    depth += 1
                } else if c == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                i += 1
            }
            found.append((start, String(code[start...min(i, code.count - 1)])))
        }
        return found
    }

    /// The braced block that follows an offset — a trailing closure, which sits
    /// *outside* the parentheses `calls(headed:)` balances and is where the work
    /// a `dropDestination` does actually lives.
    func block(after offset: Int) -> String {
        guard var i = code[min(offset, code.count)...].firstIndex(of: "{") else { return "" }
        let start = i
        var depth = 0
        var inString = false
        var escaped = false
        while i < code.count {
            let c = code[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            i += 1
        }
        return String(code[start...min(i, code.count - 1)])
    }

    /// Every single-line string literal in the code, with what is inside it.
    /// Nothing here has a `"""` block, and one would need its own scanner.
    func stringLiterals() -> [(offset: Int, contents: String)] {
        var found: [(Int, String)] = []
        var i = 0
        while i < code.count {
            guard code[i] == "\"" else { i += 1; continue }
            var body = ""
            var j = i + 1
            var escaped = false
            var closed = false
            while j < code.count {
                let c = code[j]
                if escaped { body.append(c); escaped = false }
                else if c == "\\" { body.append(c); escaped = true }
                else if c == "\"" { closed = true; break }
                else if c == "\n" { break }
                else { body.append(c) }
                j += 1
            }
            if closed { found.append((i, body)) }
            i = j + 1
        }
        return found
    }

    /// The offsets covered by calls headed by any of `patterns` — where a
    /// literal is already on its way into the catalogue.
    func spans(headedByAnyOf patterns: [String]) -> [Range<Int>] {
        patterns.flatMap { calls(headed: $0) }.map { $0.offset..<($0.offset + $0.text.count) }
    }
}
