//
//  YouTubeTranscriptError.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Errors that can occur when fetching YouTube transcripts.
///
/// All errors include the relevant video ID where applicable, making it
/// easy to log and debug issues in batch operations.
///
/// ```swift
/// do {
///     let result = try await YouTubeTranscript.fetch(videoId)
/// } catch YouTubeTranscriptError.transcriptsDisabled {
///     print("No captions on this video")
/// } catch YouTubeTranscriptError.ipBlocked {
///     print("Rate limited — try again later")
/// } catch {
///     print(error.localizedDescription)
/// }
/// ```
public enum YouTubeTranscriptError: Error, LocalizedError, Equatable, Sendable {

    /// YouTube is rate-limiting requests from this IP address.
    ///
    /// This typically happens after many rapid requests or when running
    /// from a cloud provider IP range. Wait and retry, or try from a
    /// different network.
    case ipBlocked

    /// YouTube requires CAPTCHA verification to proceed.
    ///
    /// This is more severe than ``ipBlocked`` and usually requires
    /// waiting a longer period before retrying.
    case requestBlocked

    /// The video does not exist, has been removed, or is private.
    case videoUnavailable(videoId: String)

    /// The video exists but cannot be played (e.g., region-restricted, age-gated).
    case videoUnplayable(videoId: String, reason: String)

    /// Captions/transcripts are disabled for this video by the uploader.
    case transcriptsDisabled(videoId: String)

    /// No transcript was found matching the requested languages.
    ///
    /// Check ``availableLanguages`` for what's actually available.
    case noTranscriptFound(videoId: String, requestedLanguages: [String], availableLanguages: [String])

    /// The transcript was fetched but contained no text segments.
    case emptyTranscript(videoId: String)

    /// The provided input could not be parsed as a video ID or YouTube URL.
    ///
    /// Valid inputs include:
    /// - 11-character video IDs (e.g., `"dQw4w9WgXcQ"`)
    /// - Full watch URLs, short URLs, embed URLs, Shorts URLs
    case invalidVideoId

    /// A Proof of Origin token is required for this video.
    ///
    /// This is a YouTube-side restriction that prevents automated access
    /// to certain videos. There is no workaround.
    case poTokenRequired(videoId: String)

    /// YouTube served a consent page that could not be handled.
    ///
    /// This happens in EU regions where YouTube requires cookie consent.
    /// The library attempts to handle this automatically, but it may
    /// occasionally fail.
    case consentFailed(videoId: String)

    /// A network request failed.
    case networkError(String)

    /// Failed to parse YouTube's response data.
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .ipBlocked:
            return "YouTube is rate-limiting requests from this IP. Try again later or use a different network."
        case .requestBlocked:
            return "YouTube is blocking this request and requires CAPTCHA verification."
        case .videoUnavailable(let videoId):
            return "Video is unavailable (\(videoId)). It may have been removed or set to private."
        case .videoUnplayable(let videoId, let reason):
            return "Video is unplayable (\(videoId)): \(reason)"
        case .transcriptsDisabled(let videoId):
            return "Transcripts are disabled for this video (\(videoId))."
        case .noTranscriptFound(let videoId, let requested, let available):
            return "No transcript found for \(requested.joined(separator: ", ")) on video \(videoId). Available: \(available.joined(separator: ", "))"
        case .emptyTranscript(let videoId):
            return "The transcript for video \(videoId) was empty."
        case .invalidVideoId:
            return "Could not extract a valid YouTube video ID. Pass a video ID (e.g., \"dQw4w9WgXcQ\") or a full URL."
        case .poTokenRequired(let videoId):
            return "A PO token is required to access transcripts for video \(videoId)."
        case .consentFailed(let videoId):
            return "Failed to handle YouTube's consent page for video \(videoId)."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
