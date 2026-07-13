//
//  VideoID.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//
//  Self-contained copy — this target intentionally shares no code with
//  YouTubeTranscript so the two parts of the package stay decoupled.
//

import Foundation

/// Utility for extracting YouTube video IDs from various input formats.
///
/// Supports raw 11-character IDs and all common YouTube URL patterns
/// including watch, short, embed, Shorts, live, no-cookie, and
/// parameterised URLs.
enum VideoID {

    /// Regex patterns for extracting video IDs from YouTube URLs.
    private static let patterns = [
        "(?:youtube(?:-nocookie)?\\.com/watch\\?(?:[^&\\s]*&)*v=)([a-zA-Z0-9_-]{11})",
        "(?:youtu\\.be/)([a-zA-Z0-9_-]{11})",
        "(?:youtube(?:-nocookie)?\\.com/embed/)([a-zA-Z0-9_-]{11})",
        "(?:youtube\\.com/shorts/)([a-zA-Z0-9_-]{11})",
        "(?:youtube\\.com/v/)([a-zA-Z0-9_-]{11})",
        "(?:youtube\\.com/live/)([a-zA-Z0-9_-]{11})"
    ]

    /// Extracts a YouTube video ID from a string.
    ///
    /// Accepts raw 11-character video IDs or any common YouTube URL format.
    ///
    /// - Parameter input: A video ID or YouTube URL.
    /// - Throws: ``YouTubeCommentsError/invalidVideoId`` if no valid ID can be extracted.
    /// - Returns: The 11-character video ID.
    static func extract(from input: String) throws(YouTubeCommentsError) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Raw video ID
        if trimmed.count == 11,
           trimmed.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil {
            return trimmed
        }

        // URL patterns
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = regex.firstMatch(in: trimmed, range: range),
                   let idRange = Range(match.range(at: 1), in: trimmed) {
                    return String(trimmed[idRange])
                }
            }
        }

        throw .invalidVideoId
    }
}
