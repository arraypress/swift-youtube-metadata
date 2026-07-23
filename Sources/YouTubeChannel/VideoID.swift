//
//  VideoID.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//
//  Self-contained copy — this target intentionally shares no code with the
//  other modules in the package so each stays independently usable.
//

import Foundation

/// Utility for extracting YouTube video IDs from various input formats.
///
/// Supports raw 11-character IDs and all common YouTube URL patterns including
/// watch, short, embed, Shorts, live, and no-cookie URLs.
enum VideoID {

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
    /// - Parameter input: A video ID or YouTube URL.
    /// - Throws: ``YouTubeChannelError/invalidChannel`` if no valid ID can be
    ///   extracted. (This module has no dedicated invalid-video case; an
    ///   unparseable video reference is surfaced through the same channel-input
    ///   error.)
    /// - Returns: The 11-character video ID.
    static func extract(from input: String) throws(YouTubeChannelError) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count == 11,
           trimmed.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil {
            return trimmed
        }

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = regex.firstMatch(in: trimmed, range: range),
                   let idRange = Range(match.range(at: 1), in: trimmed) {
                    return String(trimmed[idRange])
                }
            }
        }

        throw .invalidChannel
    }
}
