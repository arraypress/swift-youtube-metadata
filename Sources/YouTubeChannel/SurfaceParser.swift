//
//  SurfaceParser.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2026.
//
//  Parsers for the channel surfaces that yield something other than a video
//  grid: the playlists tab, the community tab, and a playlist's own contents.
//

import Foundation

enum SurfaceParser {

    /// One page of items plus the token that fetches the next.
    struct Page<Item> {
        let items: [Item]
        let nextToken: String?
    }

    // MARK: - Playlists Tab

    /// Parses a channel's playlists tab.
    ///
    /// Playlists and videos share the `lockupViewModel` renderer and are told
    /// apart only by `contentType`, so filtering on it is what keeps a playlist
    /// from being mistaken for a video with a `PL…` id.
    static func playlists(_ root: [String: Any]) -> Page<ChannelPlaylist> {
        var items: [ChannelPlaylist] = []
        var seen = Set<String>()

        for lockup in JSONNav.all("lockupViewModel", in: root) {
            guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_PLAYLIST",
                  let id = lockup["contentId"] as? String, !id.isEmpty,
                  seen.insert(id).inserted else { continue }

            let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]

            items.append(
                ChannelPlaylist(
                    id: id,
                    title: JSONNav.text(metadata?["title"]) ?? "",
                    videoCountText: videoCountText(in: lockup, metadata: metadata),
                    thumbnailUrl: bestImage(in: lockup["contentImage"])
                )
            )
        }

        return Page(items: items, nextToken: JSONNav.continuationToken(in: root))
    }

    /// The "N videos" line, wherever this layout happens to put it.
    ///
    /// It appears as a metadata row on some layouts and as a thumbnail overlay
    /// badge on others, so both are checked before giving up.
    private static func videoCountText(in lockup: [String: Any], metadata: [String: Any]?) -> String? {
        for part in metadataPartTexts(in: metadata?["metadata"]) where part.lowercased().contains("video") {
            return part
        }
        for badge in JSONNav.all("thumbnailBadgeViewModel", in: lockup["contentImage"]) {
            if let text = badge["text"] as? String, text.lowercased().contains("video") { return text }
        }
        return nil
    }

    // MARK: - Playlist Contents

    /// Parses a playlist page's videos.
    ///
    /// `playlistVideoRenderer` is gone — playlist entries are now the same
    /// `lockupViewModel` the channel grid uses, so this reuses the grid's own
    /// item parser rather than duplicating it.
    static func playlistVideos(_ root: [String: Any]) -> Page<ChannelVideo> {
        var items: [ChannelVideo] = []
        var seen = Set<String>()

        for lockup in JSONNav.all("lockupViewModel", in: root) {
            guard let video = ChannelParser.parseVideoLockup(lockup),
                  seen.insert(video.id).inserted else { continue }
            items.append(video)
        }

        return Page(items: items, nextToken: JSONNav.continuationToken(in: root))
    }

    // MARK: - Community Tab

    /// Parses a channel's community posts.
    static func posts(_ root: [String: Any]) -> Page<ChannelPost> {
        var items: [ChannelPost] = []
        var seen = Set<String>()

        for renderer in JSONNav.all("backstagePostRenderer", in: root) {
            guard let post = parsePost(renderer), seen.insert(post.id).inserted else { continue }
            items.append(post)
        }

        return Page(items: items, nextToken: JSONNav.continuationToken(in: root))
    }

    private static func parsePost(_ renderer: [String: Any]) -> ChannelPost? {
        guard let id = renderer["postId"] as? String, !id.isEmpty else { return nil }

        // YouTube folds the edited marker into the timestamp rather than
        // exposing a flag, e.g. "2 weeks ago (edited)". Lift it out so the
        // timestamp is a clean value and the flag is structured — leaving it in
        // both places makes every consumer report it twice.
        let raw = JSONNav.text(renderer["publishedTimeText"]) ?? ""
        let isEdited = raw.lowercased().contains("(edited)")
        let published = isEdited
            ? raw.replacingOccurrences(
                of: #"\s*\(edited\)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
              )
            : raw

        return ChannelPost(
            id: id,
            author: JSONNav.text(renderer["authorText"]) ?? "",
            text: JSONNav.text(renderer["contentText"]) ?? "",
            publishedText: published,
            likeCountText: JSONNav.text(renderer["voteCount"]),
            isEdited: isEdited,
            attachment: parseAttachment(renderer["backstageAttachment"])
        )
    }

    // MARK: - Attachments

    private static func parseAttachment(_ container: Any?) -> PostAttachment {
        guard let container = container as? [String: Any] else { return .none }

        // Order matters: a gallery also contains individual image renderers, so
        // the multi-image case must be recognised before the single-image one or
        // every gallery collapses to its first photo.
        if let multi = container["postMultiImageRenderer"] as? [String: Any] {
            let urls = JSONNav.all("backstageImageRenderer", in: multi)
                .compactMap { bestImage(in: $0["image"]) }
            if !urls.isEmpty {
                return PostAttachment(kind: .gallery, imageUrls: urls)
            }
        }

        if let image = container["backstageImageRenderer"] as? [String: Any],
           let url = bestImage(in: image["image"]) {
            return PostAttachment(kind: .image, imageUrls: [url])
        }

        if let video = container["videoRenderer"] as? [String: Any],
           let videoId = video["videoId"] as? String {
            return PostAttachment(
                kind: .video,
                videoId: videoId,
                videoTitle: JSONNav.text(video["title"])
            )
        }

        if let poll = container["pollRenderer"] as? [String: Any] {
            let choices = (poll["choices"] as? [[String: Any]] ?? [])
                .compactMap { JSONNav.text($0["text"]) }
            if !choices.isEmpty {
                return PostAttachment(kind: .poll, pollOptions: choices)
            }
        }

        return .none
    }

    // MARK: - Shared Helpers

    /// The widest image URL in a container.
    ///
    /// Handles both the legacy `thumbnails` array and the newer view-model
    /// `sources` array, which appear on different surfaces of the same page.
    private static func bestImage(in container: Any?) -> String? {
        for key in ["thumbnails", "sources"] {
            guard let candidates = JSONNav.first(key, in: container) as? [[String: Any]] else { continue }
            let widest = candidates.max {
                (($0["width"] as? Int) ?? 0) < (($1["width"] as? Int) ?? 0)
            }
            if let url = widest?["url"] as? String, !url.isEmpty { return url }
        }
        return nil
    }

    /// Flattens `contentMetadataViewModel` rows into their text parts.
    private static func metadataPartTexts(in container: Any?) -> [String] {
        var texts: [String] = []
        for row in JSONNav.all("contentMetadataViewModel", in: container) {
            guard let rows = row["metadataRows"] as? [[String: Any]] else { continue }
            for entry in rows {
                guard let parts = entry["metadataParts"] as? [[String: Any]] else { continue }
                for part in parts {
                    if let text = JSONNav.text(part["text"]), !text.isEmpty { texts.append(text) }
                }
            }
        }
        return texts
    }
}
