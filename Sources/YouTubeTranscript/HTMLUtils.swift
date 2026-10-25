//
//  HTMLUtils.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Internal utilities for HTML entity decoding and tag stripping.
enum HTMLUtils {

    /// Named HTML entities and their replacements.
    private static let namedEntities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">",
        "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "
    ]

    /// Decodes HTML entities in a string.
    ///
    /// Handles named entities (`&amp;`), decimal (`&#39;`) and hex (`&#x27;`) ones, in one pass
    /// over the text — so the order entities are tried in cannot matter — repeated until nothing
    /// changes (at most three times). YouTube's caption XML escapes its text TWICE: a speaker
    /// change `>>` arrives as `&amp;gt;&amp;gt;`. Replacing each entity once, in a dictionary's
    /// unpredictable order, left `&gt;&gt;` in transcripts whenever `&gt;` happened to go first.
    ///
    /// - Parameter text: The HTML-encoded string.
    /// - Returns: The decoded string.
    static func unescape(_ text: String) -> String {
        var result = text
        for _ in 0..<3 {
            let decoded = decodeOnce(result)
            if decoded == result { break }
            result = decoded
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One left-to-right pass: each `&…;` replaced by what it stands for; anything that is not a
    /// known entity left exactly as it was.
    static func decodeOnce(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let entity = String(text[index...semicolon])
            if let named = namedEntities[entity] {
                out += named
            } else if entity.hasPrefix("&#"), let scalar = numericScalar(entity) {
                out.unicodeScalars.append(scalar)
            } else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            index = text.index(after: semicolon)
        }
        return out
    }

    /// `&#39;` or `&#x27;` → its character.
    private static func numericScalar(_ entity: String) -> Unicode.Scalar? {
        let body = entity.dropFirst(2).dropLast()
        let value = body.first == "x" || body.first == "X" ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
        return value.flatMap(Unicode.Scalar.init)
    }

    /// Strips all HTML tags from a string.
    ///
    /// - Parameter text: The string potentially containing HTML tags.
    /// - Returns: The string with all tags removed.
    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
    }
    
}
