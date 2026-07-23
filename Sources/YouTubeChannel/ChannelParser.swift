//
//  ChannelParser.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Parses a page of channel items (videos or Shorts) out of InnerTube JSON.
///
/// Handles YouTube's current grid formats:
/// - Regular uploads and streams are `lockupViewModel`
///   (`contentType == "LOCKUP_CONTENT_TYPE_VIDEO"`), video ID in `contentId`.
/// - Shorts are `shortsLockupViewModel`, video ID in the reel watch endpoint.
///
/// The older `videoRenderer` shape is no longer emitted for channel grids. The
/// same parser reads both the initial `ytInitialData` grid and the
/// `appendContinuationItemsAction` payload returned by `youtubei/v1/browse`.
enum ChannelParser {

    /// One parsed page: the items in document order plus the token to fetch the
    /// next page (`nil` when the grid is exhausted).
    struct Page {
        let videos: [ChannelVideo]
        let nextToken: String?
    }

    /// A duration badge looks like `1:02:03`, `10:09`, or `0:42`.
    private static let durationPattern = "^(?:\\d+:)?\\d?\\d:\\d\\d$"

    /// Parses every item and the grid continuation token from `root` (either a
    /// watch-page `ytInitialData` object or a browse response).
    static func parse(_ root: [String: Any]) -> Page {
        // Grid items live inside `richItemRenderer` array elements. Collect the
        // arrays that hold them so we walk items in their true grid order (JSON
        // object key order is not preserved, but array order is).
        let itemArrays = JSONNav.arrays(in: root) { element in
            (element as? [String: Any])?["richItemRenderer"] != nil
        }

        var videos: [ChannelVideo] = []
        var seen = Set<String>()
        for array in itemArrays {
            for element in array {
                guard let item = element as? [String: Any],
                      let renderer = item["richItemRenderer"] as? [String: Any],
                      let content = renderer["content"] as? [String: Any] else { continue }

                let parsed: ChannelVideo?
                if let lockup = content["lockupViewModel"] as? [String: Any] {
                    parsed = parseVideoLockup(lockup)
                } else if let short = content["shortsLockupViewModel"] as? [String: Any] {
                    parsed = parseShortLockup(short)
                } else {
                    parsed = nil
                }

                guard let video = parsed, seen.insert(video.id).inserted else { continue }
                videos.append(video)
            }
        }

        return Page(videos: videos, nextToken: continuationToken(near: itemArrays))
    }

    // MARK: - Video lockup

    private static func parseVideoLockup(_ lockup: [String: Any]) -> ChannelVideo? {
        guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
              let id = lockup["contentId"] as? String, !id.isEmpty else { return nil }

        let meta = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        let title = JSONNav.string("content", in: meta?["title"]) ?? ""

        // The metadata rows carry "N views" and a relative date, delimited.
        var viewCountText: String?
        var publishedText: String?
        for text in metadataPartTexts(in: meta?["metadata"]) {
            if viewCountText == nil, text.lowercased().contains("view") {
                viewCountText = text
            } else if publishedText == nil, text != viewCountText {
                publishedText = text
            }
        }

        return ChannelVideo(
            id: id,
            title: title,
            lengthText: durationBadge(in: lockup),
            viewCountText: viewCountText,
            publishedText: publishedText,
            thumbnailUrl: bestThumbnail(in: lockup["contentImage"]),
            isShort: false,
            isLive: isLiveBadge(in: lockup)
        )
    }

    // MARK: - Short lockup

    private static func parseShortLockup(_ short: [String: Any]) -> ChannelVideo? {
        // Video ID lives on the reel watch endpoint under onTap.
        let endpoint = JSONNav.first("reelWatchEndpoint", in: short["onTap"])
        guard let id = JSONNav.string("videoId", in: endpoint), !id.isEmpty else { return nil }

        let overlay = short["overlayMetadata"] as? [String: Any]
        let title = JSONNav.string("content", in: overlay?["primaryText"])
            ?? JSONNav.string("content", in: short["accessibilityText"])
            ?? ""
        let views = JSONNav.string("content", in: overlay?["secondaryText"])

        return ChannelVideo(
            id: id,
            title: title,
            lengthText: nil,
            viewCountText: views,
            publishedText: nil,
            thumbnailUrl: bestThumbnail(in: short["thumbnailViewModel"]),
            isShort: true
        )
    }

    // MARK: - Field helpers

    /// Collects the rendered text of each `metadataPart` under a
    /// `contentMetadataViewModel`.
    private static func metadataPartTexts(in obj: Any?) -> [String] {
        guard let rows = JSONNav.first("metadataRows", in: obj) as? [Any] else { return [] }
        var texts: [String] = []
        for row in rows {
            guard let parts = (row as? [String: Any])?["metadataParts"] as? [Any] else { continue }
            for part in parts {
                if let text = JSONNav.string("content", in: (part as? [String: Any])?["text"]) {
                    texts.append(text)
                }
            }
        }
        return texts
    }

    /// Finds the duration overlay badge (e.g. `"10:09"`), ignoring non-duration
    /// badges such as "LIVE" or "PREMIERE".
    private static func durationBadge(in lockup: [String: Any]) -> String? {
        for badge in badgeViewModels(in: lockup) {
            if let text = badge["text"] as? String,
               text.range(of: durationPattern, options: .regularExpression) != nil {
                return text
            }
        }
        return nil
    }

    /// Detects a live badge. Verified against real live streams, whose badge is
    /// `text == "LIVE"` with `badgeStyle == "THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE"`.
    private static func isLiveBadge(in lockup: [String: Any]) -> Bool {
        for badge in badgeViewModels(in: lockup) {
            if (badge["badgeStyle"] as? String)?.uppercased().contains("LIVE") == true { return true }
            if (badge["text"] as? String)?.uppercased() == "LIVE" { return true }
        }
        return false
    }

    private static func badgeViewModels(in lockup: [String: Any]) -> [[String: Any]] {
        JSONNav.arrays(in: lockup) { ($0 as? [String: Any])?["thumbnailBadgeViewModel"] != nil }
            .flatMap { $0 }
            .compactMap { ($0 as? [String: Any])?["thumbnailBadgeViewModel"] as? [String: Any] }
    }

    /// Returns the largest thumbnail source URL found under `container`.
    /// Handles both `image.sources` (lockups) and `thumbnails` (shorts).
    private static func bestThumbnail(in container: Any?) -> String? {
        let sources = (JSONNav.first("sources", in: container) as? [Any])
            ?? (JSONNav.first("thumbnails", in: container) as? [Any])
        guard let sources else { return nil }
        var best: (w: Int, url: String)?
        for source in sources {
            guard let dict = source as? [String: Any],
                  let url = dict["url"] as? String else { continue }
            let width = dict["width"] as? Int ?? 0
            if best == nil || width > best!.w { best = (width, url) }
        }
        return best?.url
    }

    // MARK: - Continuation

    /// Picks the continuation token that is a sibling of the grid items.
    ///
    /// A channel page carries several continuation tokens (the About panel and
    /// header have their own); only the one living in the same array as the
    /// `richItemRenderer` grid items advances the item list.
    private static func continuationToken(near itemArrays: [[Any]]) -> String? {
        for array in itemArrays {
            for element in array {
                guard let dict = element as? [String: Any],
                      let renderer = dict["continuationItemRenderer"] as? [String: Any] else { continue }
                if let token = JSONNav.string("token", in: renderer) { return token }
            }
        }
        return nil
    }

    // MARK: - Channel info

    /// Extracts channel-level metadata from a watch-page `ytInitialData` object.
    ///
    /// Returns `nil` only when the essential `channelMetadataRenderer` is absent
    /// (an unexpected page shape).
    static func parseChannelInfo(_ root: [String: Any]) -> ChannelInfo? {
        guard let cmr = JSONNav.first("channelMetadataRenderer", in: root) as? [String: Any],
              let channelId = cmr["externalId"] as? String else { return nil }

        let vanity = cmr["vanityChannelUrl"] as? String
        let handle = vanity.flatMap { url -> String? in
            guard let range = url.range(of: "@[^/?&#]+", options: .regularExpression) else { return nil }
            return String(url[range])
        }

        // Subscriber / video counts live in the page header's metadata rows as
        // rendered strings like "509M subscribers" / "993 videos".
        var subscriberText: String?
        var videoCountText: String?
        if let header = JSONNav.first("pageHeaderViewModel", in: root) {
            for text in metadataPartTexts(in: header) {
                let lower = text.lowercased()
                if subscriberText == nil, lower.contains("subscriber") { subscriberText = text }
                else if videoCountText == nil, lower.contains("video") { videoCountText = text }
            }
        }

        return ChannelInfo(
            channelId: channelId,
            title: cmr["title"] as? String ?? "",
            handle: handle,
            description: cmr["description"] as? String ?? "",
            subscriberText: subscriberText,
            videoCountText: videoCountText,
            avatarUrl: bestThumbnail(in: cmr["avatar"]),
            bannerUrl: bestThumbnail(in: JSONNav.first("banner", in: root)),
            keywords: cmr["keywords"] as? String,
            vanityUrl: vanity,
            isFamilySafe: cmr["isFamilySafe"] as? Bool
        )
    }
}
