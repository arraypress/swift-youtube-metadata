//
//  FetchedTranscript+Turns.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2026.
//
//  Speaker-turn segmentation on the `>>` markers, and the turn's own
//  formatted start — behavior out of the model file.
//

import Foundation

extension TranscriptTurn {

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
