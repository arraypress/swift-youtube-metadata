//
//  PlayabilityTests.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2026.
//
//  Covers the boundary between "this video will never have a transcript",
//  "we were blocked", and "YouTube changed its response shape". Collapsing
//  these into one error tells callers to give up permanently on problems that
//  a retry or a library update would fix.
//

import XCTest
@testable import YouTubeTranscript

final class PlayabilityTests: XCTestCase {

    // MARK: - Fixtures

    /// The marker of a genuine player response.
    private let videoDetails: [String: Any] = [
        "videoId": "abc12345678",
        "title": "Sample",
        "author": "Sample Channel",
        "lengthSeconds": "213",
    ]

    private func captionsBlock(languageCodes: [String]) -> [String: Any] {
        [
            "playerCaptionsTracklistRenderer": [
                "captionTracks": languageCodes.map { code in
                    [
                        "baseUrl": "https://example.com/\(code)",
                        "languageCode": code,
                        "name": ["simpleText": code.uppercased()],
                        "kind": "",
                    ] as [String: Any]
                }
            ]
        ]
    }

    // MARK: - Track Extraction

    func testHealthyResponseWithCaptionsYieldsTracks() throws {
        let player: [String: Any] = [
            "videoDetails": videoDetails,
            "captions": captionsBlock(languageCodes: ["en", "de"]),
        ]

        let tracks = try YouTubeTranscript.extractTracks(from: player, videoId: "abc12345678")
        XCTAssertEqual(tracks.map(\.languageCode), ["en", "de"])
    }

    func testHealthyResponseWithoutCaptionsIsTranscriptsDisabled() {
        // videoDetails present, captions genuinely absent — the uploader really
        // has no transcript. The only case where a permanent verdict is right.
        let player: [String: Any] = ["videoDetails": videoDetails]

        XCTAssertThrowsError(
            try YouTubeTranscript.extractTracks(from: player, videoId: "abc12345678")
        ) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .transcriptsDisabled(videoId: "abc12345678"))
        }
    }

    func testEmptyCaptionTrackListIsTranscriptsDisabled() {
        let player: [String: Any] = [
            "videoDetails": videoDetails,
            "captions": ["playerCaptionsTracklistRenderer": ["captionTracks": [[String: Any]]()]],
        ]

        XCTAssertThrowsError(
            try YouTubeTranscript.extractTracks(from: player, videoId: "abc12345678")
        ) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .transcriptsDisabled(videoId: "abc12345678"))
        }
    }

    func testDegradedResponseIsBlockedNotDisabled() {
        // No videoDetails: a throttled or bot-checked reply. Reporting this as
        // transcriptsDisabled would tell the caller never to retry a video that
        // has a perfectly good transcript.
        let player: [String: Any] = ["responseContext": ["visitorData": "x"]]

        XCTAssertThrowsError(
            try YouTubeTranscript.extractTracks(from: player, videoId: "abc12345678")
        ) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .requestBlocked)
        }
    }

    func testRenamedRendererIsAParsingErrorNotDisabled() {
        // A captions block we cannot read means the extractor is out of date.
        let player: [String: Any] = [
            "videoDetails": videoDetails,
            "captions": ["someNewRendererName": ["captionTracks": []]],
        ]

        XCTAssertThrowsError(
            try YouTubeTranscript.extractTracks(from: player, videoId: "abc12345678")
        ) { error in
            guard case .parsingError = error as? YouTubeTranscriptError else {
                return XCTFail("Expected parsingError, got \(error)")
            }
        }
    }

    // MARK: - Playability

    func testLoginRequiredWithBotReasonIsBlocked() {
        let json: [String: Any] = [
            "playabilityStatus": ["status": "LOGIN_REQUIRED", "reason": "Sign in to confirm you're not a bot"]
        ]

        XCTAssertThrowsError(try YouTubeTranscript.checkPlayability(json, videoId: "abc")) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .requestBlocked)
        }
    }

    func testLoginRequiredWithUnrecognisedReasonIsStillBlocked() {
        // Regression: this used to fall through, letting a blocked response
        // reach track extraction and surface as transcriptsDisabled.
        let json: [String: Any] = [
            "playabilityStatus": ["status": "LOGIN_REQUIRED", "reason": "Some new wording from YouTube"]
        ]

        XCTAssertThrowsError(try YouTubeTranscript.checkPlayability(json, videoId: "abc")) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .requestBlocked)
        }
    }

    func testLoginRequiredWithEmptyReasonIsStillBlocked() {
        let json: [String: Any] = ["playabilityStatus": ["status": "LOGIN_REQUIRED"]]

        XCTAssertThrowsError(try YouTubeTranscript.checkPlayability(json, videoId: "abc")) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .requestBlocked)
        }
    }

    func testAgeRestrictionIsReportedAsUnplayableNotBlocked() {
        let json: [String: Any] = [
            "playabilityStatus": [
                "status": "LOGIN_REQUIRED",
                "reason": "This video may be inappropriate for some users",
            ]
        ]

        XCTAssertThrowsError(try YouTubeTranscript.checkPlayability(json, videoId: "abc")) { error in
            XCTAssertEqual(
                error as? YouTubeTranscriptError,
                .videoUnplayable(videoId: "abc", reason: "Age-restricted content")
            )
        }
    }

    func testUnavailableVideoIsReportedAsSuch() {
        let json: [String: Any] = [
            "playabilityStatus": ["status": "ERROR", "reason": "This video is unavailable"]
        ]

        XCTAssertThrowsError(try YouTubeTranscript.checkPlayability(json, videoId: "abc")) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .videoUnavailable(videoId: "abc"))
        }
    }

    func testOkStatusPasses() {
        let json: [String: Any] = ["playabilityStatus": ["status": "OK"]]
        XCTAssertNoThrow(try YouTubeTranscript.checkPlayability(json, videoId: "abc"))
    }

    func testMissingPlayabilityStatusPasses() {
        // Not every response carries one; extractTracks is the backstop.
        XCTAssertNoThrow(try YouTubeTranscript.checkPlayability([:], videoId: "abc"))
    }
}
