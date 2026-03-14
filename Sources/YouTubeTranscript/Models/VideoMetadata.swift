//
//  VideoMetadata.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Metadata about a YouTube video extracted alongside the transcript.
///
/// This data is retrieved from the same API call as the transcript
/// and requires no additional network requests.
///
/// ```swift
/// if let video = result.video {
///     print("\(video.title) by \(video.author)")
///     print("\(video.formattedViewCount) views · \(video.formattedDuration)")
/// }
/// ```
public struct VideoMetadata: Codable, Equatable, Sendable {

    /// The YouTube video ID.
    public let videoId: String

    /// The video title.
    public let title: String

    /// The video description (from the "About" section).
    public let description: String

    /// The channel or author name.
    public let author: String

    /// The YouTube channel ID.
    public let channelId: String

    /// Video duration in seconds.
    public let lengthSeconds: Int

    /// Total view count.
    public let viewCount: Int

    /// Keywords and tags associated with the video.
    public let keywords: [String]

    /// URL of the highest-resolution thumbnail, if available.
    public let thumbnailUrl: String?

    /// Whether this video is or was a live stream.
    public let isLive: Bool

    /// The full YouTube watch URL.
    public var url: String {
        "https://www.youtube.com/watch?v=\(videoId)"
    }

    /// The duration formatted as `"M:SS"` or `"H:MM:SS"`.
    ///
    /// ```swift
    /// // "3:32", "1:05:30"
    /// print(video.formattedDuration)
    /// ```
    public var formattedDuration: String {
        TranscriptSegment.formatTimestamp(Double(lengthSeconds))
    }

    /// The view count formatted with locale-appropriate grouping separators.
    ///
    /// ```swift
    /// // "1,500,000,000"
    /// print(video.formattedViewCount)
    /// ```
    public var formattedViewCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: viewCount)) ?? "\(viewCount)"
    }
}
