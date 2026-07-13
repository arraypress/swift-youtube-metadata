//
//  CommentExport.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Spreadsheet/JSON export helpers for a collection of ``Comment`` values.
///
/// The column order matches the common YouTube-comment export layout:
/// `publishedTimeText, simpleText, votes, author, isReply, isHearted,
/// isPinned, isPaid, paidAmount, isSponsor, sponsorshipMonths`.
public extension Sequence where Element == Comment {

    /// The export column headers, in order.
    static var exportColumns: [String] {
        ["publishedTimeText", "simpleText", "votes", "author", "isReply",
         "isHearted", "isPinned", "isPaid", "paidAmount", "isSponsor",
         "sponsorshipMonths"]
    }

    /// Renders the comments as tab-separated values.
    ///
    /// Tabs/newlines inside text are replaced with spaces so each comment stays
    /// on one row (TSV has no quoting convention).
    ///
    /// - Parameter header: Whether to include the header row. Defaults to `true`.
    func tsv(header: Bool = true) -> String {
        var lines: [String] = []
        if header { lines.append(Self.exportColumns.joined(separator: "\t")) }
        for c in self {
            lines.append(Self.row(for: c).map(Self.sanitizeTSV).joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    /// Renders the comments as RFC-4180 comma-separated values.
    ///
    /// - Parameter header: Whether to include the header row. Defaults to `true`.
    func csv(header: Bool = true) -> String {
        var lines: [String] = []
        if header { lines.append(Self.exportColumns.map(Self.escapeCSV).joined(separator: ",")) }
        for c in self {
            lines.append(Self.row(for: c).map(Self.escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    /// Encodes the comments as pretty-printed JSON.
    func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.withoutEscapingSlashes]
        return try encoder.encode(Array(self))
    }

    // MARK: - Row building

    private static func row(for c: Comment) -> [String] {
        [
            c.publishedTimeText,
            c.text,
            c.likeCountText,
            c.author,
            String(c.isReply),
            String(c.isHearted),
            String(c.isPinned),
            String(c.isPaid),
            c.paidAmount ?? "",
            String(c.isSponsor),
            c.isSponsor ? String(c.sponsorshipMonths) : ""
        ]
    }

    private static func sanitizeTSV(_ field: String) -> String {
        field
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func escapeCSV(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
