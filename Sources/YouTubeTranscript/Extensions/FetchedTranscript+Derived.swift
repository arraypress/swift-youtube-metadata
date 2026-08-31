//
//  FetchedTranscript+Derived.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2026.
//
//  The transcript's derived facts, kept out of the model file so the
//  shape reads alone.
//

import Foundation

extension FetchedTranscript {

    /// All segment text joined into a single string, separated by spaces.
    public var plainText: String {
        segments.map(\.text).joined(separator: " ")
    }

    /// Total duration of the transcript in seconds.
    ///
    /// Calculated from the last segment's start time plus its duration.
    public var duration: Double {
        guard let last = segments.last else { return 0 }
        return last.start + last.duration
    }

    /// Number of segments in the transcript.
    public var count: Int {
        segments.count
    }

    /// A human-readable label for the transcript type: `"manual"` or `"auto"`.
    public var typeLabel: String {
        isGenerated ? "auto" : "manual"
    }

    /// The total duration formatted as `"M:SS"` or `"H:MM:SS"`.
    public var formattedDuration: String {
        TranscriptSegment.formatTimestamp(duration)
    }

    /// The full transcript with timestamps, one segment per line.
    ///
    /// ```
    /// [0:00] Hello everyone
    /// [0:02] Welcome to my video
    /// ```
    public var timestampedText: String {
        segments.map { "[\($0.formattedStart)] \($0.text)" }.joined(separator: "\n")
    }
}
