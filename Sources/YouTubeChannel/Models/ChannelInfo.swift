//
//  ChannelInfo.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Channel-level metadata read from the channel page — free, since the same
/// page load that bootstraps the video enumeration already contains it.
///
/// - Note: `subscriberText` and `videoCountText` are the rounded strings
///   YouTube renders (e.g. `"509M subscribers"`, `"993 videos"`). YouTube does
///   not expose an exact subscriber count here, so they are left as text.
public struct ChannelInfo: Sendable, Equatable, Codable {

    /// The canonical channel ID (`UC…`).
    public let channelId: String

    /// The channel's display name.
    public let title: String

    /// The channel handle (e.g. `"@MrBeast"`), when derivable.
    public let handle: String?

    /// The channel description / "about" blurb.
    public let description: String

    /// Rounded subscriber text as rendered (e.g. `"509M subscribers"`).
    public let subscriberText: String?

    /// Rounded video-count text as rendered (e.g. `"993 videos"`).
    public let videoCountText: String?

    /// The largest avatar URL, when present.
    public let avatarUrl: String?

    /// The largest banner URL, when present.
    public let bannerUrl: String?

    /// The channel's raw keyword string, when present.
    public let keywords: String?

    /// The channel's vanity URL, when present.
    public let vanityUrl: String?

    /// Whether YouTube flags the channel family-safe.
    public let isFamilySafe: Bool?

    public init(
        channelId: String,
        title: String,
        handle: String? = nil,
        description: String = "",
        subscriberText: String? = nil,
        videoCountText: String? = nil,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        keywords: String? = nil,
        vanityUrl: String? = nil,
        isFamilySafe: Bool? = nil
    ) {
        self.channelId = channelId
        self.title = title
        self.handle = handle
        self.description = description
        self.subscriberText = subscriberText
        self.videoCountText = videoCountText
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.keywords = keywords
        self.vanityUrl = vanityUrl
        self.isFamilySafe = isFamilySafe
    }

    /// The canonical channel URL.
    public var url: URL? {
        URL(string: "https://www.youtube.com/channel/\(channelId)")
    }
}
