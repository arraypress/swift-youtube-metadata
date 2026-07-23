//
//  TranscriptTurnTests.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import XCTest
@testable import YouTubeTranscript

final class TranscriptTurnTests: XCTestCase {

    private func transcript(_ segs: [(String, Double, Double)]) -> FetchedTranscript {
        FetchedTranscript(
            videoId: "v",
            segments: segs.map { TranscriptSegment(text: $0.0, start: $0.1, duration: $0.2, language: "en") },
            video: nil, language: "en", isGenerated: true
        )
    }

    func testSplitsOnMarkersAndAlternatesSpeakers() {
        // A marker (`>>`) opens each new turn; a turn can span multiple segments.
        let t = transcript([
            ("Welcome to the show.", 0, 2),          // speaker 0
            (">> Thanks, happy to be here.", 2, 3),  // speaker 1
            (">> Great. Let's", 5, 1),               // speaker 0 (new marker)
            ("dive in.", 6, 1),                       // …continues speaker 0
            (">> Sounds good.", 7, 1)                 // speaker 1
        ])
        let turns = t.turns
        XCTAssertEqual(turns.count, 4)
        XCTAssertEqual(turns.map(\.speaker), [0, 1, 0, 1])
        XCTAssertEqual(turns[0].text, "Welcome to the show.")
        XCTAssertEqual(turns[0].start, 0)
        XCTAssertEqual(turns[1].text, "Thanks, happy to be here.")
        XCTAssertEqual(turns[1].start, 2)
        // The multi-segment turn is merged and starts at its marker.
        XCTAssertEqual(turns[2].text, "Great. Let's dive in.")
        XCTAssertEqual(turns[2].start, 5)
        XCTAssertEqual(turns[3].text, "Sounds good.")
    }

    func testNoMarkersYieldsSingleTurn() {
        let t = transcript([("just", 0, 1), ("one speaker", 1, 1)])
        let turns = t.turns
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].text, "just one speaker")
        XCTAssertEqual(turns[0].speaker, 0)
    }

    func testHandlesRawEntityMarkers() {
        // Some tracks arrive with the marker still HTML-escaped.
        let t = transcript([("Hi &gt;&gt; Hello back", 0, 2)])
        let turns = t.turns
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].text, "Hi")
        XCTAssertEqual(turns[1].text, "Hello back")
    }
}
