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
        // Match any `<text …>content</text>` element, then read `start`/`dur`
        // from its attributes independently. YouTube occasionally omits `dur`
        // (e.g. final/ASR segments) or reorders attributes; a rigid
        // `start="…" dur="…"` pattern would silently drop those segments — and
        // dropping enough of them yields a spurious `emptyTranscript`.
        guard let elementRegex = try? NSRegularExpression(
            pattern: "<text([^>]*)>(.*?)</text>",
            options: .dotMatchesLineSeparators
        ) else { return [] }

        let nsXml = xml as NSString
        let range = NSRange(location: 0, length: nsXml.length)

        return elementRegex.matches(in: xml, range: range).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }

            let attributes = nsXml.substring(with: match.range(at: 1))
            let rawText = nsXml.substring(with: match.range(at: 2))

            let text = HTMLUtils.unescape(HTMLUtils.stripTags(rawText))
            guard !text.isEmpty else { return nil }

            return TranscriptSegment(
                text: text,
                start: attributeValue("start", in: attributes).flatMap(Double.init) ?? 0,
                duration: attributeValue("dur", in: attributes).flatMap(Double.init) ?? 0,
                language: language
            )
        }
    }

    /// Extracts a quoted attribute value (e.g. `start="1.5"`) from an element's
    /// attribute string, regardless of attribute order. Returns `nil` if absent.
    private static func attributeValue(_ name: String, in attributes: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)=\"([^\"]*)\"") else { return nil }
        let ns = attributes as NSString
        guard let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
