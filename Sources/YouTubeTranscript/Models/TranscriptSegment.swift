//
//  TranscriptSegment.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// A single timed segment of a transcript.
///
/// Each segment represents a portion of text displayed during a specific
/// time window of the video.
///
/// ```swift
/// for segment in result.segments {
///     print("[\(segment.formattedStart)] \(segment.text)")
/// }
/// ```
public struct TranscriptSegment: Codable, Equatable, Sendable {

    /// The text content of this segment.
    public let text: String

    /// The start time in seconds from the beginning of the video.
    public let start: Double

    /// How long this segment is displayed in seconds.
    ///
    /// Note: This is the display duration, not speech duration.
    /// Segments may overlap slightly.
    public let duration: Double

    /// The language code of this segment (e.g., `"en"`, `"de"`).
    public let language: String

}
