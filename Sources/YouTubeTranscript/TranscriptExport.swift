//
//  TranscriptExport.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Subtitle-file export helpers for a fetched transcript.
///
/// ```swift
/// let t = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")
/// try t.srt().write(to: url, atomically: true, encoding: .utf8)
/// ```
public extension FetchedTranscript {

    /// Renders the transcript as SubRip (`.srt`) subtitles.
    ///
    /// Cue timings use `start → start + duration`. Where consecutive segments
    /// overlap (common with auto-generated captions), each cue's end is clamped
    /// to the next cue's start so players don't show two cues at once.
    func srt() -> String {
        let cues = clampedCues()
        var out = ""
        for (index, cue) in cues.enumerated() {
            out += "\(index + 1)\n"
            out += "\(Self.timestamp(cue.start, millisSeparator: ","))"
            out += " --> "
            out += "\(Self.timestamp(cue.end, millisSeparator: ","))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    /// Renders the transcript as WebVTT (`.vtt`) subtitles.
    ///
    /// Same cue clamping as ``srt()``. A `WEBVTT` header is emitted, and the
    /// three characters that are structural in VTT cue text (`&`, `<`, `>`) are
    /// escaped.
    func vtt() -> String {
        let cues = clampedCues()
        var out = "WEBVTT\n\n"
        for cue in cues {
            out += "\(Self.timestamp(cue.start, millisSeparator: "."))"
            out += " --> "
            out += "\(Self.timestamp(cue.end, millisSeparator: "."))\n"
            out += "\(Self.escapeVTT(cue.text))\n\n"
        }
        return out
    }

    // MARK: - Cue preparation

    private struct Cue {
        let start: Double
        let end: Double
        let text: String
    }

    /// Segments turned into non-overlapping cues, dropping empty text.
    private func clampedCues() -> [Cue] {
        let usable = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return usable.enumerated().map { index, segment in
            var end = segment.end
            if index + 1 < usable.count {
                end = min(end, usable[index + 1].start)
            }
            // Guard against zero/negative-length cues from clamping.
            if end <= segment.start { end = segment.start + 0.001 }
            return Cue(start: segment.start, end: end, text: segment.text)
        }
    }

    // MARK: - Formatting

    /// Formats seconds as `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm` (VTT).
    private static func timestamp(_ seconds: Double, millisSeparator: String) -> String {
        let totalMs = Int((max(0, seconds) * 1000).rounded())
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, millisSeparator, ms)
    }

    private static func escapeVTT(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
