//
//  YouTubeSearchError.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Errors thrown while searching YouTube.
///
/// The cases separate three situations that look alike from the outside but
/// call for different responses: YouTube declining to serve us (retryable), a
/// query or channel that genuinely has nothing (permanent), and a response we
/// can no longer read (needs a library update).
public enum YouTubeSearchError: Error, LocalizedError, Equatable, Sendable {

    /// YouTube is refusing requests from this IP address.
    case ipBlocked

    /// YouTube served a bot check or consent wall instead of results.
    case requestBlocked

    /// The query was empty or only whitespace.
    case emptyQuery

    /// The channel does not exist, is terminated, or exposes no public content.
    case channelUnavailable(channel: String)

    /// A network-level failure.
    case networkError(String)

    /// The response could not be understood — YouTube has changed its shape and
    /// the parser needs updating.
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .ipBlocked:
            return "YouTube is blocking requests from this IP address."
        case .requestBlocked:
            return "YouTube rejected the request as automated traffic."
        case .emptyQuery:
            return "The search query is empty."
        case .channelUnavailable(let channel):
            return "Channel is unavailable (\(channel)). It may not exist, be terminated, or have no public content."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Could not parse YouTube's response: \(message)"
        }
    }
}
