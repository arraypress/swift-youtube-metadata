//
//  ChannelPlaylist.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One playlist on a channel's playlists tab.
///
/// The listing carries only the playlist's identity and size. To enumerate its
/// videos, pass ``id`` to ``YouTubeChannel/playlist(_:limit:configuration:)``.
public struct ChannelPlaylist: Codable, Equatable, Sendable, Identifiable {

    /// The playlist ID, e.g. `"PLoYRB6C09WUCe5iQ6N-PKm_-jux0yzf5y"`.
    public let id: String

    /// The playlist title.
    public let title: String

    /// Size as shown, e.g. `"12 videos"`. Absent on some layouts.
    public let videoCountText: String?

    /// The largest available thumbnail URL.
    public let thumbnailUrl: String?

    public init(
        id: String,
        title: String,
        videoCountText: String? = nil,
        thumbnailUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.videoCountText = videoCountText
        self.thumbnailUrl = thumbnailUrl
    }

    /// The canonical playlist URL.
    public var url: URL? {
        URL(string: "https://www.youtube.com/playlist?list=\(id)")
    }
}
