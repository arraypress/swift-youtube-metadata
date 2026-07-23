//
//  VideoDetailsParser.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Extracts exact per-video statistics from an InnerTube `player` response.
enum VideoDetailsParser {

    /// Parses `videoDetails` + `microformat` into a ``VideoDetails``.
    ///
    /// Returns `nil` only when the response carries no `videoDetails` at all
    /// (e.g. a removed or fully private video).
    static func parse(_ json: [String: Any], videoId: String) -> VideoDetails? {
        guard let details = json["videoDetails"] as? [String: Any] else { return nil }

        let microformat = (json["microformat"] as? [String: Any])?["playerMicroformatRenderer"] as? [String: Any]

        return VideoDetails(
            id: details["videoId"] as? String ?? videoId,
            title: details["title"] as? String ?? "",
            viewCount: (details["viewCount"] as? String).flatMap(Int.init),
            lengthSeconds: (details["lengthSeconds"] as? String).flatMap(Int.init),
            publishDate: microformat?["publishDate"] as? String,
            uploadDate: microformat?["uploadDate"] as? String,
            description: details["shortDescription"] as? String ?? "",
            category: microformat?["category"] as? String,
            author: details["author"] as? String ?? "",
            channelId: details["channelId"] as? String ?? "",
            keywords: details["keywords"] as? [String] ?? [],
            isLiveContent: details["isLiveContent"] as? Bool ?? false
        )
    }
}
