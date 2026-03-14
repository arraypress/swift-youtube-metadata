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
    /// Handles named entities (e.g., `&amp;`) and numeric entities (e.g., `&#123;`).
    ///
    /// - Parameter text: The HTML-encoded string.
    /// - Returns: The decoded string.
    static func unescape(_ text: String) -> String {
        var result = text

        for (entity, char) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        // Numeric entities: &#123;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let range = NSRange(result.startIndex..., in: result)
            let nsString = result as NSString
            for match in regex.matches(in: result, range: range).reversed() {
                let numStr = nsString.substring(with: match.range(at: 1))
                if let code = Int(numStr), let scalar = Unicode.Scalar(code) {
                    if let matchRange = Range(match.range, in: result) {
                        result.replaceSubrange(matchRange, with: String(Character(scalar)))
                    }
                }
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips all HTML tags from a string.
    ///
    /// - Parameter text: The string potentially containing HTML tags.
    /// - Returns: The string with all tags removed.
    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
    }
    
}
