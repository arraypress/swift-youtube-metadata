//
//  ChannelPost.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2026.
//

import Foundation

// MARK: - Attachment

/// What a community post carries alongside its text.
///
/// Modelled as a struct with a `kind` discriminator rather than an enum with
/// associated values so that it encodes flat. Agents reading the JSON and the
/// CSV/Markdown exporters both want predictable keys, not a tagged union that
/// changes shape per case.
///
/// The multi-image case is the one that matters: a post with a six-image
/// gallery uses a different renderer from a single-image post, and a model with
/// one `imageUrl` field would silently discard five of the six.
public struct PostAttachment: Codable, Equatable, Sendable {

    /// The kind of attachment, if any.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case none
        case image
        case gallery
        case video
        case poll
    }

    public let kind: Kind

    /// Image URLs. One entry for ``Kind/image``, several for ``Kind/gallery``.
    public let imageUrls: [String]

    /// The attached video's ID, for ``Kind/video``.
    public let videoId: String?

    /// The attached video's title, for ``Kind/video``.
    public let videoTitle: String?

    /// Poll choices, for ``Kind/poll``.
    public let pollOptions: [String]

    public init(
        kind: Kind = .none,
        imageUrls: [String] = [],
        videoId: String? = nil,
        videoTitle: String? = nil,
        pollOptions: [String] = []
    ) {
        self.kind = kind
        self.imageUrls = imageUrls
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.pollOptions = pollOptions
    }

    /// An attachment carrying nothing.
    public static let none = PostAttachment()
}

// MARK: - Post

/// One post from a channel's community tab.
public struct ChannelPost: Codable, Equatable, Sendable, Identifiable {

    /// The post ID, e.g. `"Ugkx1edjTsXBOanGC2EmRo-Z…"`.
    public let id: String

    /// The posting channel's display name.
    public let author: String

    /// The post body, with rich-text runs flattened. Newlines are preserved.
    public let text: String

    /// Relative publish time as shown, e.g. `"12 days ago"`.
    public let publishedText: String

    /// Like count as shown, e.g. `"277"`.
    public let likeCountText: String?

    /// Whether YouTube marks the post as edited.
    public let isEdited: Bool

    /// What the post carries besides text.
    public let attachment: PostAttachment

    public init(
        id: String,
        author: String,
        text: String,
        publishedText: String,
        likeCountText: String? = nil,
        isEdited: Bool = false,
        attachment: PostAttachment = .none
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.publishedText = publishedText
        self.likeCountText = likeCountText
        self.isEdited = isEdited
        self.attachment = attachment
    }

    /// The canonical post URL — also what the comments API is keyed on.
    public var url: URL? {
        URL(string: "https://www.youtube.com/post/\(id)")
    }
}
