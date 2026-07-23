//
//  VideoDetails.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Exact per-video statistics that the channel grid does not carry — fetched
/// with one InnerTube `player` request per video via
/// ``YouTubeChannel/details(for:configuration:)``.
///
/// Unlike ``ChannelVideo``'s rounded grid strings, these are precise: the true
/// integer view count, the length in seconds, and the ISO-8601 publish date.
///
/// - Note: Like counts are intentionally omitted — YouTube no longer exposes a
///   reliable public like count through this endpoint.
public struct VideoDetails: Sendable, Equatable, Codable {

    /// The 11-character YouTube video ID.
    public let id: String

    /// The full video title.
    public let title: String

    /// Exact view count.
    public let viewCount: Int?

    /// Exact duration in seconds.
    public let lengthSeconds: Int?

    /// ISO-8601 publish date (e.g. `"2026-06-27T09:00:05-07:00"`), when present.
    public let publishDate: String?

    /// ISO-8601 upload date, when present.
    public let uploadDate: String?

    /// The full (untruncated) video description.
    public let description: String

    /// The video's category (e.g. `"Entertainment"`), when present.
    public let category: String?

    /// Author/channel display name.
    public let author: String

    /// The owning channel's ID (`UC…`).
    public let channelId: String

    /// Search keywords/tags the uploader set, when present.
    public let keywords: [String]

    /// Whether the item is (or was) live content.
    public let isLiveContent: Bool

    public init(
        id: String,
        title: String,
        viewCount: Int? = nil,
        lengthSeconds: Int? = nil,
        publishDate: String? = nil,
        uploadDate: String? = nil,
        description: String = "",
        category: String? = nil,
        author: String = "",
        channelId: String = "",
        keywords: [String] = [],
        isLiveContent: Bool = false
    ) {
        self.id = id
        self.title = title
        self.viewCount = viewCount
        self.lengthSeconds = lengthSeconds
        self.publishDate = publishDate
        self.uploadDate = uploadDate
        self.description = description
        self.category = category
        self.author = author
        self.channelId = channelId
        self.keywords = keywords
        self.isLiveContent = isLiveContent
    }
}
