//
//  YouTubeChannelError.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Errors that can occur when enumerating a YouTube channel's uploads.
///
/// ```swift
/// do {
///     let ids = try await YouTubeChannel.videoIDs("@GoogleDevelopers")
/// } catch YouTubeChannelError.channelUnavailable {
///     print("No such channel, or it has no public videos")
/// } catch YouTubeChannelError.ipBlocked {
///     print("Rate limited — try again later")
/// } catch {
///     print(error.localizedDescription)
/// }
/// ```
public enum YouTubeChannelError: Error, LocalizedError, Equatable, Sendable {

    /// YouTube is rate-limiting requests from this IP address.
    ///
    /// This typically happens after many rapid requests or when running
    /// from a cloud provider IP range. Wait and retry, or try from a
    /// different network. See ``YouTubeChannel/Configuration`` for the
    /// built-in retry/backoff options.
    case ipBlocked

    /// YouTube requires CAPTCHA verification to proceed.
    ///
    /// This is more severe than ``ipBlocked`` and usually requires
    /// waiting a longer period before retrying.
    case requestBlocked

    /// The provided input could not be parsed as a channel ID, handle, or URL.
    ///
    /// Valid inputs include:
    /// - Channel IDs (e.g., `"UC_x5XG1OV2P6uZZ5FSM9Ttw"`)
    /// - Handles (e.g., `"@GoogleDevelopers"`)
    /// - Channel URLs (`/channel/UC…`, `/@handle`, `/c/name`, `/user/name`)
    case invalidChannel

    /// The channel does not exist, is terminated, or exposes no public uploads.
    case channelUnavailable(channel: String)

    /// YouTube served a consent page that could not be handled.
    ///
    /// This happens in EU regions where YouTube requires cookie consent.
    /// The library attempts to handle this automatically, but it may
    /// occasionally fail.
    case consentFailed(channel: String)

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
        case .invalidChannel:
            return "Could not parse a YouTube channel. Pass a channel ID (\"UC…\"), a handle (\"@name\"), or a channel URL."
        case .channelUnavailable(let channel):
            return "Channel is unavailable (\(channel)). It may not exist, be terminated, or have no public videos."
        case .consentFailed(let channel):
            return "Failed to handle YouTube's consent page for channel \(channel)."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
