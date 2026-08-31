//
//  TranscriptTurn.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// A single speaker turn, reconstructed from a transcript's `>>`
/// speaker-change markers.
///
/// ```swift
/// let result = try await YouTubeTranscript.fetch(videoId)
/// for turn in result.turns {
///     print("[\(turn.formattedStart)] Speaker \(turn.speaker + 1): \(turn.text)")
/// }
/// ```
public struct TranscriptTurn: Sendable, Equatable, Codable {

    /// A best-effort speaker index that **alternates** (0, 1, 0, 1, …) on each
    /// `>>` change marker.
    ///
    /// - Important: YouTube captions carry no speaker *names*, only change
    ///   markers, and auto-generated tracks mark changes imperfectly. So this is
    ///   an approximation — reliable as a *turn* boundary, only a heuristic as
    ///   *speaker identity* (it assumes a two-party, strictly-alternating
    ///   conversation). For true diarization you need the audio and an ML model.
    public let speaker: Int

    /// The turn's text, with the `>>` markers removed.
    public let text: String

    /// The start time in seconds from the beginning of the video.
    public let start: Double

    /// The end time in seconds.
    public let end: Double

    public init(speaker: Int, text: String, start: Double, end: Double) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }

}
