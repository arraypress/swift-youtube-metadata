//
//  YouTubeTranscriptTests.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import XCTest
@testable import YouTubeTranscript

final class YouTubeTranscriptTests: XCTestCase {

    // MARK: - Video ID Extraction

    func testExtractRawId() throws {
        XCTAssertEqual(try VideoID.extract(from: "dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromWatchUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromShortUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromEmbedUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/embed/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromShortsUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromLiveUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/live/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromUrlWithParams() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PLtest"), "dQw4w9WgXcQ")
    }

    func testExtractWithWhitespace() throws {
        XCTAssertEqual(try VideoID.extract(from: "  dQw4w9WgXcQ  "), "dQw4w9WgXcQ")
    }

    func testExtractInvalidThrows() {
        XCTAssertThrowsError(try VideoID.extract(from: "not-a-valid-video-id")) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .invalidVideoId)
        }
    }

    func testExtractEmptyStringThrows() {
        XCTAssertThrowsError(try VideoID.extract(from: "")) { error in
            XCTAssertEqual(error as? YouTubeTranscriptError, .invalidVideoId)
        }
    }

    // MARK: - HTML Utils

    func testUnescapeNamedEntities() {
        XCTAssertEqual(HTMLUtils.unescape("&amp;"), "&")
        XCTAssertEqual(HTMLUtils.unescape("&lt;b&gt;"), "<b>")
        XCTAssertEqual(HTMLUtils.unescape("it&#39;s"), "it's")
        XCTAssertEqual(HTMLUtils.unescape("&quot;hello&quot;"), "\"hello\"")
    }

    func testUnescapeNumericEntities() {
        XCTAssertEqual(HTMLUtils.unescape("&#65;"), "A")
        XCTAssertEqual(HTMLUtils.unescape("&#97;"), "a")
    }

    func testStripTags() {
        XCTAssertEqual(HTMLUtils.stripTags("<b>bold</b>"), "bold")
        XCTAssertEqual(HTMLUtils.stripTags("no tags"), "no tags")
        XCTAssertEqual(HTMLUtils.stripTags("<font color=\"red\">text</font>"), "text")
    }

    // MARK: - Transcript Parser

    func testParseSimpleXml() {
        let xml = """
        <transcript>
            <text start="0.0" dur="2.5">Hello everyone</text>
            <text start="2.5" dur="3.0">Welcome to my video</text>
        </transcript>
        """

        let segments = TranscriptParser.parse(xml, language: "en")
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "Hello everyone")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].duration, 2.5)
        XCTAssertEqual(segments[0].language, "en")
        XCTAssertEqual(segments[1].text, "Welcome to my video")
        XCTAssertEqual(segments[1].start, 2.5)
    }

    func testParseXmlWithHtmlEntities() {
        let xml = """
        <text start="0.0" dur="1.0">it&#39;s &amp; that&#39;s</text>
        """

        let segments = TranscriptParser.parse(xml, language: "en")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "it's & that's")
    }

    func testParseXmlWithInnerTags() {
        let xml = """
        <text start="0.0" dur="1.0"><font color="#CCCCCC">styled text</font></text>
        """

        let segments = TranscriptParser.parse(xml, language: "en")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "styled text")
    }

    func testParseEmptyXml() {
        let segments = TranscriptParser.parse("", language: "en")
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - TranscriptSegment Convenience

    func testFormattedStart() {
        let segment = TranscriptSegment(text: "test", start: 65.5, duration: 1, language: "en")
        XCTAssertEqual(segment.formattedStart, "1:05")
    }

    func testFormattedStartHours() {
        let segment = TranscriptSegment(text: "test", start: 3661, duration: 1, language: "en")
        XCTAssertEqual(segment.formattedStart, "1:01:01")
    }

    func testFormattedStartZero() {
        let segment = TranscriptSegment(text: "test", start: 0, duration: 1, language: "en")
        XCTAssertEqual(segment.formattedStart, "0:00")
    }

    func testSegmentEnd() {
        let segment = TranscriptSegment(text: "test", start: 10, duration: 2.5, language: "en")
        XCTAssertEqual(segment.end, 12.5)
    }

    // MARK: - TranscriptTrack Convenience

    func testTrackTypeLabel() {
        let manual = TranscriptTrack(languageCode: "en", language: "English", isGenerated: false, isTranslatable: true, baseUrl: "url")
        let generated = TranscriptTrack(languageCode: "en", language: "English", isGenerated: true, isTranslatable: true, baseUrl: "url")
        XCTAssertEqual(manual.typeLabel, "manual")
        XCTAssertEqual(generated.typeLabel, "auto")
    }

    // MARK: - TranscriptList

    func testFindTrackPrefersManual() {
        let manual = TranscriptTrack(languageCode: "en", language: "English", isGenerated: false, isTranslatable: true, baseUrl: "url1")
        let generated = TranscriptTrack(languageCode: "en", language: "English (auto)", isGenerated: true, isTranslatable: true, baseUrl: "url2")

        let list = TranscriptList(videoId: "test", tracks: [generated, manual])
        let found = list.findTrack(languages: ["en"])
        XCTAssertEqual(found?.isGenerated, false)
    }

    func testFindTrackFallsBackToSecondLanguage() {
        let german = TranscriptTrack(languageCode: "de", language: "German", isGenerated: false, isTranslatable: true, baseUrl: "url1")
        let english = TranscriptTrack(languageCode: "en", language: "English", isGenerated: true, isTranslatable: true, baseUrl: "url2")

        let list = TranscriptList(videoId: "test", tracks: [german, english])
        let found = list.findTrack(languages: ["fr", "en"])
        XCTAssertEqual(found?.languageCode, "en")
    }

    func testFindTrackReturnsNilWhenNotFound() {
        let german = TranscriptTrack(languageCode: "de", language: "German", isGenerated: false, isTranslatable: true, baseUrl: "url1")

        let list = TranscriptList(videoId: "test", tracks: [german])
        XCTAssertNil(list.findTrack(languages: ["fr", "es"]))
    }

    func testManualAndGeneratedFilters() {
        let manual = TranscriptTrack(languageCode: "en", language: "English", isGenerated: false, isTranslatable: true, baseUrl: "url1")
        let generated = TranscriptTrack(languageCode: "en", language: "English (auto)", isGenerated: true, isTranslatable: true, baseUrl: "url2")

        let list = TranscriptList(videoId: "test", tracks: [manual, generated])
        XCTAssertEqual(list.manualTracks.count, 1)
        XCTAssertEqual(list.generatedTracks.count, 1)
        XCTAssertEqual(list.availableLanguages, ["en", "en"])
    }

    // MARK: - FetchedTranscript

    func testPlainText() {
        let segments = [
            TranscriptSegment(text: "Hello", start: 0, duration: 1, language: "en"),
            TranscriptSegment(text: "World", start: 1, duration: 1, language: "en"),
        ]
        let result = FetchedTranscript(videoId: "test", segments: segments, video: nil, language: "en", isGenerated: false)
        XCTAssertEqual(result.plainText, "Hello World")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.duration, 2.0)
    }

    func testTimestampedText() {
        let segments = [
            TranscriptSegment(text: "Hello", start: 0, duration: 1, language: "en"),
            TranscriptSegment(text: "World", start: 65, duration: 1, language: "en"),
        ]
        let result = FetchedTranscript(videoId: "test", segments: segments, video: nil, language: "en", isGenerated: false)
        XCTAssertEqual(result.timestampedText, "[0:00] Hello\n[1:05] World")
    }

    func testTypeLabel() {
        let auto = FetchedTranscript(videoId: "test", segments: [], video: nil, language: "en", isGenerated: true)
        let manual = FetchedTranscript(videoId: "test", segments: [], video: nil, language: "en", isGenerated: false)
        XCTAssertEqual(auto.typeLabel, "auto")
        XCTAssertEqual(manual.typeLabel, "manual")
    }

    func testFormattedDuration() {
        let segments = [
            TranscriptSegment(text: "End", start: 3600 + 120 + 5, duration: 2, language: "en"),
        ]
        let result = FetchedTranscript(videoId: "test", segments: segments, video: nil, language: "en", isGenerated: false)
        XCTAssertEqual(result.formattedDuration, "1:02:07")
    }

    func testEmptyTranscript() {
        let result = FetchedTranscript(videoId: "test", segments: [], video: nil, language: "en", isGenerated: false)
        XCTAssertEqual(result.plainText, "")
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.duration, 0)
    }

    // MARK: - Error Descriptions

    func testAllErrorsHaveDescriptions() {
        let errors: [YouTubeTranscriptError] = [
            .ipBlocked,
            .requestBlocked,
            .videoUnavailable(videoId: "test"),
            .videoUnplayable(videoId: "test", reason: "restricted"),
            .transcriptsDisabled(videoId: "test"),
            .noTranscriptFound(videoId: "test", requestedLanguages: ["en"], availableLanguages: ["de"]),
            .emptyTranscript(videoId: "test"),
            .invalidVideoId,
            .poTokenRequired(videoId: "test"),
            .consentFailed(videoId: "test"),
            .networkError("timeout"),
            .parsingError("bad json"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Transcript Parsing

    func testParseStandardSegments() {
        let xml = "<transcript><text start=\"0.0\" dur=\"2.5\">Hello</text><text start=\"2.5\" dur=\"3.0\">World &amp; more</text></transcript>"
        let segments = TranscriptParser.parse(xml, language: "en")
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "Hello")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].duration, 2.5)
        XCTAssertEqual(segments[1].text, "World & more")
    }

    /// A `<text>` element with no `dur` must NOT be dropped (previously it was).
    func testParseSegmentMissingDuration() {
        let xml = "<text start=\"5.0\">Final line</text>"
        let segments = TranscriptParser.parse(xml, language: "en")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Final line")
        XCTAssertEqual(segments[0].start, 5.0)
        XCTAssertEqual(segments[0].duration, 0)
    }

    /// Attribute order must not matter (previously `dur` had to follow `start`).
    func testParseSegmentReorderedAttributes() {
        let xml = "<text dur=\"1.5\" start=\"9.0\">Reordered</text>"
        let segments = TranscriptParser.parse(xml, language: "en")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 9.0)
        XCTAssertEqual(segments[0].duration, 1.5)
    }

    func testErrorEquatable() {
        XCTAssertEqual(YouTubeTranscriptError.ipBlocked, .ipBlocked)
        XCTAssertEqual(YouTubeTranscriptError.invalidVideoId, .invalidVideoId)
        XCTAssertNotEqual(YouTubeTranscriptError.ipBlocked, .requestBlocked)
    }

    // MARK: - Integration Tests (require network)

    func testFetchRickAstley() async throws {
        let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")

        XCTAssertFalse(result.segments.isEmpty)
        XCTAssertFalse(result.plainText.isEmpty)
        XCTAssertEqual(result.videoId, "dQw4w9WgXcQ")

        // Metadata should be present
        XCTAssertNotNil(result.video)
        XCTAssertFalse(result.video?.title.isEmpty ?? true)
        XCTAssertFalse(result.video?.author.isEmpty ?? true)
        XCTAssertGreaterThan(result.video?.viewCount ?? 0, 0)
        XCTAssertGreaterThan(result.video?.lengthSeconds ?? 0, 0)
    }

    func testFetchWithFullUrl() async throws {
        let result = try await YouTubeTranscript.fetch("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertFalse(result.segments.isEmpty)
        XCTAssertEqual(result.videoId, "dQw4w9WgXcQ")
    }

    func testFetchMetadataFields() async throws {
        let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")
        let video = try XCTUnwrap(result.video)

        XCTAssertEqual(video.videoId, "dQw4w9WgXcQ")
        XCTAssertFalse(video.title.isEmpty)
        XCTAssertFalse(video.description.isEmpty)
        XCTAssertFalse(video.author.isEmpty)
        XCTAssertFalse(video.channelId.isEmpty)
        XCTAssertGreaterThan(video.lengthSeconds, 100) // ~3.5 min video
        XCTAssertGreaterThan(video.viewCount, 1_000_000)
    }

    func testListAvailableTranscripts() async throws {
        let list = try await YouTubeTranscript.list("dQw4w9WgXcQ")

        XCTAssertEqual(list.videoId, "dQw4w9WgXcQ")
        XCTAssertFalse(list.tracks.isEmpty)
        XCTAssertFalse(list.availableLanguages.isEmpty)
        XCTAssertTrue(list.availableLanguages.contains(where: { $0.hasPrefix("en") }))
    }

    func testFetchNonexistentVideoThrows() async {
        do {
            _ = try await YouTubeTranscript.fetch("xxxxxxxxxxx")
            XCTFail("Should throw for nonexistent video")
        } catch {
            // Any error is expected
        }
    }
}
