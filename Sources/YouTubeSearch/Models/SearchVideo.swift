//
//  SearchVideo.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One video in a set of search results.
///
/// Search returns the same rounded, human-formatted figures the results page
/// shows ("1.2M views", "3 years ago") rather than exact numbers. For precise
/// statistics on a specific video, follow up with the `YouTubeChannel` module's
/// `details(for:)`.
public struct SearchVideo: Codable, Equatable, Sendable, Identifiable {

    /// The 11-character video ID.
    public let id: String

    /// The video title.
    public let title: String

    /// The uploading channel's display name.
    public let author: String

    /// The uploading channel's ID, when the result carries one.
    public let channelId: String?

    /// Duration as shown, e.g. `"10:01"`. Absent for live streams.
    public let lengthText: String?

    /// View count as shown, e.g. `"1.2M views"`.
    public let viewCountText: String?

    /// Relative publish date as shown, e.g. `"3 years ago"`.
    public let publishedText: String?

    /// The description snippet shown beneath the result, when present.
    public let description: String?

    /// The largest available thumbnail URL.
    public let thumbnailUrl: String?

    /// Whether the result is a live broadcast.
    public let isLive: Bool

    public init(
        id: String,
        title: String,
        author: String = "",
        channelId: String? = nil,
        lengthText: String? = nil,
        viewCountText: String? = nil,
        publishedText: String? = nil,
        description: String? = nil,
        thumbnailUrl: String? = nil,
        isLive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.channelId = channelId
        self.lengthText = lengthText
        self.viewCountText = viewCountText
        self.publishedText = publishedText
        self.description = description
        self.thumbnailUrl = thumbnailUrl
        self.isLive = isLive
    }

    /// The canonical watch URL.
    public var url: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}
