//
//  SearchFiltersTests.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//
//  The `sp` parameter is a base64 protobuf. These tests pin the encoding against
//  the values youtube.com itself produces, so a regression here shows up as a
//  failing assertion rather than as silently unfiltered results.
//

import XCTest
@testable import YouTubeSearch

final class SearchFiltersTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultFiltersSendNoParameter() {
        let filters = SearchFilters()
        XCTAssertTrue(filters.isDefault)
        XCTAssertNil(filters.parameter, "Relevance with no filters must not send sp at all")
    }

    // MARK: - Sort Orders

    func testSortOrdersMatchYouTubesOwnValues() {
        // Verified against youtube.com's &sp= values.
        XCTAssertEqual(SearchFilters(sortBy: .rating).parameter, "CAE=")
        XCTAssertEqual(SearchFilters(sortBy: .uploadDate).parameter, "CAI=")
        XCTAssertEqual(SearchFilters(sortBy: .viewCount).parameter, "CAM=")
    }

    // MARK: - Filters

    func testTypeVideoMatchesYouTubesValue() {
        XCTAssertEqual(SearchFilters(type: .video).parameter, "EgIQAQ==")
    }

    func testUploadDateTodayWithTypeVideoMatchesYouTubesValue() {
        let filters = SearchFilters(uploadDate: .today, type: .video)
        XCTAssertEqual(filters.parameter, "EgQIAhAB")
    }

    func testDurationOccupiesFieldThree() {
        // 0x12 (field 2, message) 0x02 (length) 0x18 (field 3, varint) 0x02
        let filters = SearchFilters(duration: .long)
        XCTAssertEqual(filters.parameter, "EgIYAg==")
    }

    // MARK: - Combinations

    func testSortAndFiltersCombine() {
        // This combination has no published constant to copy — encoding it is
        // the entire reason for building the protobuf rather than a lookup table.
        let filters = SearchFilters(
            sortBy: .viewCount,
            uploadDate: .thisWeek,
            type: .video,
            duration: .long
        )

        let encoded = try? XCTUnwrap(filters.parameter)
        let decoded = Data(base64Encoded: encoded ?? "")
        XCTAssertEqual(
            [UInt8](decoded ?? Data()),
            [
                0x08, 0x03,             // sortBy = viewCount
                0x12, 0x06,             // filters message, 6 bytes
                0x08, 0x03,             //   uploadDate = thisWeek
                0x10, 0x01,             //   type = video
                0x18, 0x02,             //   duration = over20Minutes
            ]
        )
    }

    func testEveryParameterIsValidBase64() {
        for sort in SearchFilters.SortBy.allCases {
            for date in SearchFilters.UploadDate.allCases {
                let filters = SearchFilters(sortBy: sort, uploadDate: date, type: .video)
                let parameter = filters.parameter
                XCTAssertNotNil(parameter)
                XCTAssertNotNil(Data(base64Encoded: parameter ?? ""), "Not decodable: \(parameter ?? "nil")")
            }
        }
    }

    func testIsDefaultTracksEveryField() {
        XCTAssertFalse(SearchFilters(sortBy: .uploadDate).isDefault)
        XCTAssertFalse(SearchFilters(uploadDate: .today).isDefault)
        XCTAssertFalse(SearchFilters(type: .video).isDefault)
        XCTAssertFalse(SearchFilters(duration: .short).isDefault)
    }

    // MARK: - URLs

    func testResultsURLCarriesQueryAndFilters() throws {
        let url = try SearchURL.results(
            query: "swift concurrency",
            filters: SearchFilters(sortBy: .uploadDate)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)

        XCTAssertEqual(components.host, "www.youtube.com")
        XCTAssertEqual(components.path, "/results")
        XCTAssertEqual(items.first { $0.name == "search_query" }?.value, "swift concurrency")
        XCTAssertEqual(items.first { $0.name == "sp" }?.value, "CAI=")
    }

    func testResultsURLOmitsSPWhenUnfiltered() throws {
        let url = try SearchURL.results(query: "test", filters: SearchFilters())
        XCTAssertFalse(url.absoluteString.contains("sp="))
    }

    func testEmptyQueryIsRejected() {
        XCTAssertThrowsError(try SearchURL.results(query: "   ", filters: SearchFilters())) { error in
            XCTAssertEqual(error as? YouTubeSearchError, .emptyQuery)
        }
        XCTAssertThrowsError(try SearchURL.channel("@name", query: "")) { error in
            XCTAssertEqual(error as? YouTubeSearchError, .emptyQuery)
        }
    }

    // MARK: - Channel References

    func testHandleBecomesAChannelSearchURL() throws {
        let url = try SearchURL.channel("@RickAstleyYT", query: "never")
        XCTAssertEqual(url.path, "/@RickAstleyYT/search")
        XCTAssertTrue(url.absoluteString.contains("query=never"))
    }

    func testBareChannelIDBecomesAChannelPath() throws {
        let url = try SearchURL.channel("UCuAXFkgsw1L7xaCfnd5JJOw", query: "x")
        XCTAssertEqual(url.path, "/channel/UCuAXFkgsw1L7xaCfnd5JJOw/search")
    }

    func testBareWordIsTreatedAsAHandle() throws {
        let url = try SearchURL.channel("RickAstleyYT", query: "x")
        XCTAssertEqual(url.path, "/@RickAstleyYT/search")
    }

    func testTabPathIsStrippedFromAFullURL() throws {
        // "/videos/search" is not a real surface; the tab must be dropped.
        let url = try SearchURL.channel("https://www.youtube.com/@RickAstleyYT/videos", query: "x")
        XCTAssertEqual(url.path, "/@RickAstleyYT/search")
    }

    func testChannelURLFormIsAccepted() throws {
        let url = try SearchURL.channel(
            "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
            query: "x"
        )
        XCTAssertEqual(url.path, "/channel/UCuAXFkgsw1L7xaCfnd5JJOw/search")
    }

    func testNonYouTubeURLIsRejected() {
        XCTAssertThrowsError(try SearchURL.channel("https://example.com/@someone", query: "x"))
    }
}
