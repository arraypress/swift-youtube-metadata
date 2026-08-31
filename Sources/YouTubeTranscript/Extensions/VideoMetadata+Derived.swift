//
//  VideoMetadata+Derived.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2026.
//
//  The video's derived facts, formatting delegated into Support.
//

import Foundation

extension VideoMetadata {

    /// The full YouTube watch URL.
    public var url: String {
        "https://www.youtube.com/watch?v=\(videoId)"
    }

    /// The duration formatted as `"M:SS"` or `"H:MM:SS"`.
    public var formattedDuration: String {
        Formatting.timestamp(seconds: Double(lengthSeconds))
    }

    /// The view count formatted with locale-appropriate grouping separators.
    public var formattedViewCount: String {
        Formatting.count(viewCount)
    }
}
