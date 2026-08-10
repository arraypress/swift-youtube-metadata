//
//  SearchParser.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turns InnerTube search JSON into ``SearchVideo`` values.
enum SearchParser {

    /// One page of results plus the token that fetches the next.
    struct Page {
        let videos: [SearchVideo]
        let nextToken: String?
    }

    // MARK: - Parsing

    /// Collects every video result in the tree, in document order.
    ///
    /// Results are spread across several `itemSectionRenderer` sections —
    /// promoted slots, "people also watched" shelves, and the results proper —
    /// and YouTube reorders them freely. Collecting every `videoRenderer`
    /// wherever it sits survives that; a hard-coded key path does not.
    static func parse(_ root: [String: Any]) -> Page {
        var videos: [SearchVideo] = []
        var seen = Set<String>()

        for renderer in JSONNav.all("videoRenderer", in: root) {
            guard let video = parseVideo(renderer), seen.insert(video.id).inserted else { continue }
            videos.append(video)
        }

        return Page(videos: videos, nextToken: continuationToken(in: root))
    }

    // MARK: - Video

    private static func parseVideo(_ renderer: [String: Any]) -> SearchVideo? {
        guard let id = renderer["videoId"] as? String, !id.isEmpty,
              let title = JSONNav.text(renderer["title"]) else { return nil }

        let author = JSONNav.text(renderer["ownerText"])
            ?? JSONNav.text(renderer["longBylineText"])
            ?? JSONNav.text(renderer["shortBylineText"])
            ?? ""

        let channelId = JSONNav.string("browseId", in: renderer["ownerText"])
            ?? JSONNav.string("browseId", in: renderer["longBylineText"])

        // The snippet lives under `detailedMetadataSnippets` on the results page
        // and under `descriptionSnippet` in continuation responses.
        let description = JSONNav.text(JSONNav.first("snippetText", in: renderer["detailedMetadataSnippets"]))
            ?? JSONNav.text(renderer["descriptionSnippet"])

        return SearchVideo(
            id: id,
            title: title,
            author: author,
            channelId: channelId,
            lengthText: JSONNav.text(renderer["lengthText"]),
            viewCountText: JSONNav.text(renderer["viewCountText"]),
            publishedText: JSONNav.text(renderer["publishedTimeText"]),
            description: description,
            thumbnailUrl: bestThumbnail(in: renderer["thumbnail"]),
            isLive: isLive(renderer)
        )
    }

    // MARK: - Helpers

    /// Whether the result is a live broadcast.
    ///
    /// Live results carry a `LIVE` badge and no duration, so the badge is the
    /// reliable signal — a missing `lengthText` alone also matches premieres and
    /// the occasional malformed result.
    private static func isLive(_ renderer: [String: Any]) -> Bool {
        for badge in JSONNav.all("metadataBadgeRenderer", in: renderer["badges"]) {
            if let style = badge["style"] as? String, style.contains("LIVE") { return true }
        }
        for overlay in JSONNav.all("thumbnailOverlayTimeStatusRenderer", in: renderer["thumbnailOverlays"]) {
            if let style = overlay["style"] as? String, style.contains("LIVE") { return true }
        }
        return false
    }

    /// The widest thumbnail offered.
    private static func bestThumbnail(in container: Any?) -> String? {
        guard let thumbnails = JSONNav.first("thumbnails", in: container) as? [[String: Any]] else {
            return nil
        }
        let widest = thumbnails.max {
            (($0["width"] as? Int) ?? 0) < (($1["width"] as? Int) ?? 0)
        }
        return widest?["url"] as? String
    }

    /// The token that fetches the next page, if there is one.
    private static func continuationToken(in root: Any?) -> String? {
        for renderer in JSONNav.all("continuationItemRenderer", in: root) {
            if let token = JSONNav.string("token", in: renderer) { return token }
        }
        return nil
    }
}
