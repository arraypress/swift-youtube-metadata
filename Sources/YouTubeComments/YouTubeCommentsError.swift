//
//  YouTubeCommentsError.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Errors that can occur when fetching YouTube comments.
///
/// All errors include the relevant video ID where applicable, making it
/// easy to log and debug issues in batch operations.
///
/// ```swift
/// do {
///     let comments = try await YouTubeComments.fetch(videoId)
/// } catch YouTubeCommentsError.commentsDisabled {
///     print("Comments are turned off for this video")
/// } catch YouTubeCommentsError.ipBlocked {
///     print("Rate limited — try again later")
/// } catch {
///     print(error.localizedDescription)
/// }
/// ```
public enum YouTubeCommentsError: Error, LocalizedError, Equatable, Sendable {

    /// YouTube is rate-limiting requests from this IP address.
    ///
    /// This typically happens after many rapid requests or when running
    /// from a cloud provider IP range. Wait and retry, or try from a
    /// different network. See ``YouTubeComments/Configuration`` for the
    /// built-in retry/backoff options.
    case ipBlocked

    /// YouTube requires CAPTCHA verification to proceed.
    ///
    /// This is more severe than ``ipBlocked`` and usually requires
    /// waiting a longer period before retrying.
    case requestBlocked

    /// The video does not exist, has been removed, or is private.
    case videoUnavailable(videoId: String)

    /// Comments are disabled for this video by the uploader,
    /// or the video has no comment surface at all.
    case commentsDisabled(videoId: String)

    /// The provided input could not be parsed as a video ID or YouTube URL.
    ///
    /// Valid inputs include:
    /// - 11-character video IDs (e.g., `"dQw4w9WgXcQ"`)
    /// - Full watch URLs, short URLs, embed URLs, Shorts URLs, live URLs
    case invalidVideoId

    /// YouTube served a consent page that could not be handled.
    ///
    /// This happens in EU regions where YouTube requires cookie consent.
    /// The library attempts to handle this automatically, but it may
    /// occasionally fail.
    case consentFailed(videoId: String)

    /// A network request failed (timeout, DNS, offline, etc.).
    case networkError(String)

    /// Failed to parse YouTube's response data.
    ///
    /// Usually indicates that YouTube changed its internal response
    /// structure. Please file an issue if you see this consistently.
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .ipBlocked:
            return "YouTube is rate-limiting requests from this IP. Try again later or use a different network."
        case .requestBlocked:
            return "YouTube is blocking this request and requires CAPTCHA verification."
        case .videoUnavailable(let videoId):
            return "Video is unavailable (\(videoId)). It may have been removed or set to private."
        case .commentsDisabled(let videoId):
            return "Comments are disabled for this video (\(videoId))."
        case .invalidVideoId:
            return "Could not extract a valid YouTube video ID. Pass a video ID (e.g., \"dQw4w9WgXcQ\") or a full URL."
        case .consentFailed(let videoId):
            return "Failed to handle YouTube's consent page for video \(videoId)."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
