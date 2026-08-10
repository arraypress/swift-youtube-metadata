//
//  SearchURL.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Builds the page URLs that bootstrap a search.
enum SearchURL {

    // MARK: - Site Search

    /// The results page for a site-wide search.
    ///
    /// - Parameters:
    ///   - query: The search terms.
    ///   - filters: Ordering and filters, encoded into `sp`.
    static func results(query: String, filters: SearchFilters) throws(YouTubeSearchError) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyQuery }

        var components = URLComponents(string: "https://www.youtube.com/results")
        var items = [
            URLQueryItem(name: "search_query", value: trimmed),
            URLQueryItem(name: "hl", value: "en"),
        ]
        if let parameter = filters.parameter {
            items.append(URLQueryItem(name: "sp", value: parameter))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw .parsingError("Could not build a search URL for \"\(trimmed)\"")
        }
        return url
    }

    // MARK: - Channel Search

    /// The search tab of one channel.
    ///
    /// Accepts the same channel references the rest of the package does: a
    /// channel ID, an `@handle`, or any channel URL.
    static func channel(_ input: String, query: String) throws(YouTubeSearchError) -> URL {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw .emptyQuery }

        let base = try channelBase(input)

        var components = URLComponents(string: base + "/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: trimmedQuery),
            URLQueryItem(name: "hl", value: "en"),
        ]

        guard let url = components?.url else {
            throw .channelUnavailable(channel: input)
        }
        return url
    }

    /// Normalises a channel reference to a base URL with no trailing path.
    private static func channelBase(_ input: String) throws(YouTubeSearchError) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .channelUnavailable(channel: input) }

        // A full URL: strip any tab path so "/videos" does not become
        // "/videos/search".
        if trimmed.lowercased().hasPrefix("http") {
            guard let url = URL(string: trimmed), let host = url.host, host.contains("youtube.") else {
                throw .channelUnavailable(channel: input)
            }
            let parts = url.path.split(separator: "/").map(String.init)
            guard let first = parts.first else { throw .channelUnavailable(channel: input) }

            if first.hasPrefix("@") {
                return "https://www.youtube.com/\(first)"
            }
            if ["channel", "c", "user"].contains(first), parts.count > 1 {
                return "https://www.youtube.com/\(first)/\(parts[1])"
            }
            throw .channelUnavailable(channel: input)
        }

        if trimmed.hasPrefix("@") {
            return "https://www.youtube.com/\(trimmed)"
        }
        if trimmed.hasPrefix("UC"), trimmed.count == 24 {
            return "https://www.youtube.com/channel/\(trimmed)"
        }

        // A bare word is treated as a handle, which is how youtube.com resolves
        // it too.
        return "https://www.youtube.com/@\(trimmed)"
    }
}
