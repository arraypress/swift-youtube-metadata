//
//  ChannelURL.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Which channel tab to enumerate.
///
/// All tabs share the same InnerTube grid + continuation mechanism; they differ
/// only in the URL segment and the lockup renderer used for their items.
public enum ContentTab: String, Sendable, CaseIterable, Codable {
    /// Regular long-form uploads (`/videos`).
    case videos
    /// Shorts (`/shorts`). Items are parsed as ``ChannelVideo`` with
    /// ``ChannelVideo/isShort`` set.
    case shorts
    /// Past and current live streams (`/streams`).
    case streams
}

/// A channel surface whose items are not videos.
///
/// Kept separate from ``ContentTab`` because these return different models —
/// folding them in as extra tab cases would make the return type of a tab fetch
/// depend on the tab, which the API cannot express.
public enum ChannelSurface: String, Sendable, CaseIterable, Codable {
    /// The playlists tab (`/playlists`).
    case playlists
    /// The community tab (`/posts`).
    case posts
}

/// Normalises the many ways of referring to a YouTube channel into the URL of
/// one of that channel's tabs.
///
/// The tab page already embeds the first page of items plus the grid
/// continuation token, so resolving a handle or custom URL costs nothing extra:
/// the same page fetch that bootstraps the InnerTube credentials also yields
/// the first batch of items and the channel-level metadata.
///
/// Accepted inputs:
/// - Channel IDs: `"UC_x5XG1OV2P6uZZ5FSM9Ttw"`
/// - Handles: `"@GoogleDevelopers"` (or a bare `"GoogleDevelopers"`)
/// - Channel URLs: `/channel/UC…`, `/@handle`, `/c/name`, `/user/name`
enum ChannelURL {

    /// A channel ID is `UC` followed by 22 URL-safe base64 characters.
    private static let channelIDPattern = "UC[0-9A-Za-z_-]{22}"

    /// Builds the `…/<tab>?hl=en` URL for whatever channel reference `input`
    /// describes.
    ///
    /// - Throws: ``YouTubeChannelError/invalidChannel`` when `input` matches no
    ///   known channel form.
    static func url(from input: String, tab: ContentTab = .videos) throws(YouTubeChannelError) -> URL {
        build(path: try resolvePath(input), segment: tab.rawValue)
    }

    /// Builds the URL of a channel surface that yields something other than a
    /// video grid.
    static func url(from input: String, surface: ChannelSurface) throws(YouTubeChannelError) -> URL {
        build(path: try resolvePath(input), segment: surface.rawValue)
    }

    /// Builds the URL of a playlist's own contents page.
    ///
    /// Accepts a bare playlist ID or any URL carrying a `list=` parameter.
    /// Playlist IDs are not all `PL…` — uploads feeds are `UU…`, mixes `RD…`,
    /// likes `LL…` — so the prefix is not used as a validity test.
    static func playlistURL(from input: String) throws(YouTubeChannelError) -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidChannel }

        let identifier: String
        if trimmed.lowercased().contains("list=") {
            guard let extracted = firstMatch("[?&]list=([^&#\\s]+)", in: trimmed) else {
                throw .invalidChannel
            }
            identifier = extracted
        } else if trimmed.range(of: "^[A-Za-z0-9_-]{2,}$", options: .regularExpression) != nil {
            identifier = trimmed
        } else {
            throw .invalidChannel
        }

        guard let url = URL(string: "https://www.youtube.com/playlist?list=\(identifier)&hl=en") else {
            throw .invalidChannel
        }
        return url
    }

    // MARK: - Helpers

    /// Reduces any accepted channel reference to its URL path component.
    private static func resolvePath(_ input: String) throws(YouTubeChannelError) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidChannel }

        // 1. Bare channel ID.
        if trimmed.range(of: "^\(channelIDPattern)$", options: .regularExpression) != nil {
            return "channel/\(trimmed)"
        }

        // 2. Handle with an explicit "@".
        if trimmed.hasPrefix("@") {
            return sanitisePathComponent(trimmed)
        }

        // 3. Any YouTube URL — pull the channel reference out of the path.
        if trimmed.contains("youtube.com") || trimmed.contains("youtu.be") {
            if let id = firstMatch("/(\(channelIDPattern))", in: trimmed) {
                return "channel/\(id)"
            }
            if let handle = firstMatch("/(@[^/?&#\\s]+)", in: trimmed) {
                return sanitisePathComponent(handle)
            }
            if let legacy = firstMatch("/((?:c|user)/[^/?&#\\s]+)", in: trimmed) {
                return sanitisePathComponent(legacy)
            }
            throw .invalidChannel
        }

        // 4. A bare token with no scheme and no "@": treat it as a handle, which
        //    is how modern YouTube addresses channels (e.g. "GoogleDevelopers").
        if trimmed.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil {
            return "@\(trimmed)"
        }

        throw .invalidChannel
    }

    private static func build(path: String, segment: String) -> URL {
        // Assembled from components so anything URL-illegal in the path — a
        // pasted handle like "@my channel" survives resolvePath — is percent-
        // encoded rather than trapping `URL(string:)`. A nonsense handle then
        // surfaces as `channelUnavailable`, the same way the search module
        // treats it.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/\(path)/\(segment)"
        components.queryItems = [URLQueryItem(name: "hl", value: "en")]
        return components.url!
    }

    /// Strips a trailing `/videos` (or other tab) and query/fragment so we can
    /// re-append `/videos` cleanly.
    private static func sanitisePathComponent(_ component: String) -> String {
        var value = component
        if let cut = value.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            value = String(value[..<cut])
        }
        while value.hasSuffix("/") { value.removeLast() }
        // Drop a trailing tab segment like "/videos", "/streams", "/featured".
        for tab in ["/videos", "/streams", "/shorts", "/featured", "/playlists", "/posts", "/community", "/about", "/search"] where value.hasSuffix(tab) {
            value.removeLast(tab.count)
            break
        }
        return value
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
