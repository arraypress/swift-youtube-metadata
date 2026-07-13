//
//  Comment.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// A single YouTube comment (top-level comment or reply).
///
/// Extracted from YouTube's internal InnerTube API, this captures everything
/// the web client shows for a comment — including data the official YouTube
/// Data API does *not* expose, such as creator hearts, pinned status,
/// membership badges, and paid "Super Thanks" chips.
///
/// ```swift
/// let comments = try await YouTubeComments.fetch("dQw4w9WgXcQ")
/// for c in comments where !c.isReply {
///     print("\(c.author): \(c.text) — \(c.likeCountText) likes")
///     if c.isPinned { print("  📌 \(c.pinnedByText ?? "pinned")") }
///     if c.isHearted { print("  ❤️ hearted by creator") }
/// }
/// ```
public struct Comment: Codable, Equatable, Sendable, Identifiable {

    /// The unique comment ID.
    ///
    /// For replies this is `"<parentId>.<replyId>"`, so it contains a `.`.
    public let id: String

    /// The comment's text content.
    ///
    /// Corresponds to the `simpleText` column in a spreadsheet export.
    public let text: String

    /// The author's channel handle, e.g. `"@GamerZakh"`.
    public let author: String

    /// The author's YouTube channel ID (e.g. `"UC..."`).
    public let authorChannelId: String

    /// URL of the author's avatar thumbnail, if available.
    public let authorAvatarUrl: String?

    /// The relative publish time exactly as YouTube displays it.
    ///
    /// May include an edited marker, e.g. `"1 month ago"` or
    /// `"1 month ago (edited)"`.
    public let publishedTimeText: String

    /// Whether the comment has been edited (derived from ``publishedTimeText``).
    public let isEdited: Bool

    /// The like count exactly as YouTube displays it.
    ///
    /// Abbreviated for large values, e.g. `"16"`, `"1.2K"`, `"85K"`. This is
    /// the `votes` column in a spreadsheet export. YouTube does not expose an
    /// exact count for large numbers via this API; use ``likeCount`` for a
    /// best-effort integer.
    public let likeCountText: String

    /// A best-effort integer parse of ``likeCountText`` (`"85K"` → `85000`).
    public let likeCount: Int

    /// The number of direct replies to this comment.
    ///
    /// Only meaningful for top-level comments; `0` for replies.
    public let replyCount: Int

    /// Whether this comment is a reply to another comment.
    public let isReply: Bool

    /// The parent comment's ID, if this is a reply; otherwise `nil`.
    public let parentId: String?

    /// Whether the video's creator gave this comment a ❤️ (heart).
    public let isHearted: Bool

    /// Whether this comment is pinned by the creator.
    public let isPinned: Bool

    /// The pinned-by label if pinned, e.g. `"Pinned by @GamerZakh"`.
    public let pinnedByText: String?

    /// Whether the author's channel is verified.
    public let isVerified: Bool

    /// Whether the author is the channel owner (the video's creator).
    public let isChannelOwner: Bool

    /// Whether this is a paid "Super Thanks" comment.
    public let isPaid: Bool

    /// The paid amount as displayed, e.g. `"£2.00"`, if ``isPaid`` is `true`.
    public let paidAmount: String?

    /// Whether the author is a channel member (sponsor).
    public let isSponsor: Bool

    /// The author's total membership length in months, if a member.
    ///
    /// Parsed from the badge label (`"Member (3 years, 4 months)"` → `40`).
    /// `0` for new members or when the length is not shown.
    public let sponsorshipMonths: Int

    /// The raw membership badge label, e.g. `"Member (5 months)"`, if a member.
    public let sponsorBadgeText: String?

    /// A permalink to this comment.
    public var url: String {
        let base = "https://www.youtube.com/watch?v=\(videoId)&lc=\(id)"
        return base
    }

    /// The video ID this comment belongs to.
    public let videoId: String
}
