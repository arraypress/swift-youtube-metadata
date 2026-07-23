//
//  ChannelVideo.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// A single item discovered on a channel tab (a normal upload, a Short, or a
/// past live stream).
///
/// The fields mirror what YouTube renders in the grid: enough to identify and
/// describe an item without a second request. For exact numbers — precise view
/// count, publish date, description, duration in seconds — call
/// ``YouTubeChannel/details(for:configuration:)`` with ``id``, or feed ``id``
/// into the sibling `YouTubeTranscript` / `YouTubeComments` modules.
///
/// - Note: `viewCountText`, `publishedText`, and `lengthText` are the
///   human-readable strings exactly as YouTube renders them (e.g. `"4.7K views"`,
///   `"1 day ago"`, `"10:09"`). They are localisation- and format-dependent and
///   deliberately left unparsed — the raw string is the honest representation of
///   what the grid provides. Shorts expose a title and view count but no
///   duration or publish text.
public struct ChannelVideo: Sendable, Equatable, Identifiable, Codable {

    /// The 11-character YouTube video ID.
    public let id: String

    /// The video title.
    public let title: String

    /// Duration badge text as rendered (e.g. `"10:09"`), or `nil` for items
    /// without one (Shorts, and some live/upcoming entries).
    public let lengthText: String?

    /// View-count text as rendered (e.g. `"4.7K views"`), when present.
    public let viewCountText: String?

    /// Relative publish text as rendered (e.g. `"1 day ago"`), when present.
    public let publishedText: String?

    /// The largest thumbnail URL YouTube offered for this item, when present.
    public let thumbnailUrl: String?

    /// `true` when this item is a Short (parsed from the Shorts tab or a Shorts
    /// lockup), rather than a regular video.
    public let isShort: Bool

    /// `true` when the item is currently live streaming.
    public let isLive: Bool

    public init(
        id: String,
        title: String,
        lengthText: String? = nil,
        viewCountText: String? = nil,
        publishedText: String? = nil,
        thumbnailUrl: String? = nil,
        isShort: Bool = false,
        isLive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.lengthText = lengthText
        self.viewCountText = viewCountText
        self.publishedText = publishedText
        self.thumbnailUrl = thumbnailUrl
        self.isShort = isShort
        self.isLive = isLive
    }

    /// The canonical short URL for this video.
    public var url: URL? {
        URL(string: "https://youtu.be/\(id)")
    }
}
