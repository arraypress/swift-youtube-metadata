//
//  TranscriptParser.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Parses YouTube's XML transcript format into ``TranscriptSegment`` arrays.
///
/// YouTube returns transcripts as XML with `<text>` elements containing
/// `start` and `dur` attributes:
///
/// ```xml
/// <text start="0.0" dur="2.5">Hello everyone</text>
/// <text start="2.5" dur="3.0">Welcome to my &amp; video</text>
/// ```
///
/// The parser handles HTML entities and inline formatting tags.
enum TranscriptParser {

    /// Parses XML transcript content into an array of segments.
    ///
    /// - Parameters:
    ///   - xml: The raw XML string from YouTube's timedtext endpoint.
    ///   - language: The language code to attach to each segment.
    /// - Returns: An array of ``TranscriptSegment`` values.
    static func parse(_ xml: String, language: String) -> [TranscriptSegment] {
        guard let regex = try? NSRegularExpression(
            pattern: "<text start=\"([^\"]*)\" dur=\"([^\"]*)\"[^>]*>(.*?)</text>",
            options: .dotMatchesLineSeparators
        ) else { return [] }

        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)

        return matches.compactMap { match in
            guard match.numberOfRanges >= 4 else { return nil }

            let nsXml = xml as NSString
            let startStr = nsXml.substring(with: match.range(at: 1))
            let durStr = nsXml.substring(with: match.range(at: 2))
            let rawText = nsXml.substring(with: match.range(at: 3))

            let text = HTMLUtils.unescape(HTMLUtils.stripTags(rawText))
            guard !text.isEmpty else { return nil }

            return TranscriptSegment(
                text: text,
                start: Double(startStr) ?? 0,
                duration: Double(durStr) ?? 0,
                language: language
            )
        }
    }
}
