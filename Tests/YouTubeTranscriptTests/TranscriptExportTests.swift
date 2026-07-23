//
//  TranscriptExportTests.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import XCTest
@testable import YouTubeTranscript

final class TranscriptExportTests: XCTestCase {

    private func make(_ segments: [(String, Double, Double)]) -> FetchedTranscript {
        FetchedTranscript(
            videoId: "vid",
            segments: segments.map { TranscriptSegment(text: $0.0, start: $0.1, duration: $0.2, language: "en") },
            video: nil,
            language: "en",
            isGenerated: true
        )
    }

    func testSRTBasicFormat() {
        let t = make([("Hello everyone", 0, 2), ("Second line", 2.5, 1.5)])
        let srt = t.srt()
        let expected = """
        1
        00:00:00,000 --> 00:00:02,000
        Hello everyone

        2
        00:00:02,500 --> 00:00:04,000
        Second line


        """
        XCTAssertEqual(srt, expected)
    }

    func testVTTHeaderAndDotSeparator() {
        let t = make([("Hi", 1, 1)])
        let vtt = t.vtt()
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(vtt.contains("00:00:01.000 --> 00:00:02.000"))
    }

    func testOverlapClampedToNextStart() {
        // First cue lasts until 3.0 but the next starts at 2.0 → clamp to 2.0.
        let t = make([("A", 0, 3), ("B", 2, 2)])
        let srt = t.srt()
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:02,000"), "overlap should clamp to next start")
    }

    func testHoursTimestamp() {
        let t = make([("Late", 3661.5, 1)]) // 1:01:01.500
        XCTAssertTrue(t.srt().contains("01:01:01,500 --> "))
    }

    func testVTTEscaping() {
        let t = make([("a < b & c > d", 0, 1)])
        XCTAssertTrue(t.vtt().contains("a &lt; b &amp; c &gt; d"))
    }

    func testEmptySegmentsDropped() {
        let t = make([("real", 0, 1), ("   ", 1, 1), ("also real", 2, 1)])
        let srt = t.srt()
        XCTAssertTrue(srt.contains("real"))
        XCTAssertTrue(srt.contains("also real"))
        // Only two cues → numbering ends at 2.
        XCTAssertTrue(srt.contains("2\n"))
        XCTAssertFalse(srt.contains("3\n"))
    }
}
