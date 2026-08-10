//
//  PostID.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Extracts a community post ID from the forms a caller might pass.
enum PostID {

    /// Returns the post ID in `input`, or `input` itself if it is already one.
    ///
    /// Deliberately permissive rather than validating a prefix. Post IDs are
    /// opaque and have used several prefixes over time (`Ugkx…`, `UgyQ…`, `Ugw…`),
    /// so rejecting unfamiliar ones would break on YouTube's next variant —
    /// whereas passing an id through and letting the fetch fail produces an
    /// accurate error either way.
    static func extract(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Any URL carrying /post/<id>, with optional query or fragment.
        if let range = trimmed.range(of: "/post/") {
            let tail = trimmed[range.upperBound...]
            let id = tail.prefix { $0 != "/" && $0 != "?" && $0 != "#" && !$0.isWhitespace }
            if !id.isEmpty { return String(id) }
        }

        // The `lb` parameter used by some share links.
        if let regex = try? NSRegularExpression(pattern: "[?&]lb=([^&#\\s]+)"),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges > 1,
           let captured = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[captured])
        }

        return trimmed
    }
}
