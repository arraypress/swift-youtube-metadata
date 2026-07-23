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

    /// The start time formatted as `"M:SS"` or `"H:MM:SS"`.
    public var formattedStart: String {
        TranscriptSegment.formatTimestamp(start)
    }
}

public extension FetchedTranscript {

    /// Groups the transcript's segments into speaker ``TranscriptTurn``s using the
    /// `>>` change markers some caption tracks include.
    ///
    /// Returns a single turn when the track has no `>>` markers (e.g. most
    /// single-speaker videos, or tracks that omit them). See
    /// ``TranscriptTurn/speaker`` for the accuracy caveats — this is faithful as
    /// turn segmentation, approximate as speaker identity.
    var turns: [TranscriptTurn] {
        var result: [TranscriptTurn] = []
        var speaker = 0
        var buffer = ""
        var turnStart: Double?
        var lastEnd: Double = 0

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let start = turnStart {
                result.append(TranscriptTurn(speaker: speaker % 2, text: trimmed, start: start, end: lastEnd))
            }
            buffer = ""
        }

        for segment in segments {
            // Tolerate both decoded (`>>`) and raw (`&gt;&gt;`) markers.
            let normalized = segment.text.replacingOccurrences(of: "&gt;&gt;", with: ">>")
            let parts = normalized.components(separatedBy: ">>")
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    // Crossed a `>>` boundary: close the current turn, open the next.
                    flush()
                    speaker += 1
                    turnStart = segment.start
                }
                if turnStart == nil { turnStart = segment.start }
                if !part.isEmpty {
                    if !buffer.isEmpty, !buffer.hasSuffix(" ") { buffer += " " }
                    buffer += part.trimmingCharacters(in: .whitespaces)
                }
            }
            lastEnd = segment.end
        }
        flush()
        return result
    }
}
