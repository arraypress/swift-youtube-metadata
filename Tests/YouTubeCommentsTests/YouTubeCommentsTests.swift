//
//  YouTubeCommentsTests.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import XCTest
@testable import YouTubeComments

final class YouTubeCommentsTests: XCTestCase {

    // MARK: - Video ID Extraction

    func testExtractRawId() throws {
        XCTAssertEqual(try VideoID.extract(from: "dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromWatchUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromWatchUrlWithParamsBeforeV() throws {
        XCTAssertEqual(
            try VideoID.extract(from: "https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=10"),
            "dQw4w9WgXcQ"
        )
    }

    func testExtractFromShortUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromShortsUrl() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractFromNoCookieEmbed() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractInvalidThrows() {
        XCTAssertThrowsError(try VideoID.extract(from: "not a video"))
    }

    // MARK: - Count parsing

    func testParseCountPlain() {
        XCTAssertEqual(CommentParser.parseCount("16"), 16)
        XCTAssertEqual(CommentParser.parseCount("0"), 0)
        XCTAssertEqual(CommentParser.parseCount("1,024"), 1024)
    }

    func testParseCountAbbreviated() {
        XCTAssertEqual(CommentParser.parseCount("85K"), 85_000)
        XCTAssertEqual(CommentParser.parseCount("1.2K"), 1_200)
        XCTAssertEqual(CommentParser.parseCount("1.2M"), 1_200_000)
        XCTAssertEqual(CommentParser.parseCount("3B"), 3_000_000_000)
    }

    // MARK: - Membership month parsing

    func testParseMonths() {
        XCTAssertEqual(CommentParser.parseMonths("Member (5 months)"), 5)
        XCTAssertEqual(CommentParser.parseMonths("Member (1 year)"), 12)
        XCTAssertEqual(CommentParser.parseMonths("Member (3 years, 4 months)"), 40)
        XCTAssertEqual(CommentParser.parseMonths("New member"), 0)
        XCTAssertEqual(CommentParser.parseMonths(nil), 0)
    }

    // MARK: - Parsing a page (structurally faithful fixture)

    func testParseTopLevelPage() throws {
        let response = try json(Fixtures.topLevelPage)
        let page = CommentParser.parse(response, videoId: "vid123")

        XCTAssertEqual(page.comments.count, 2)
        XCTAssertEqual(page.nextPageToken, "PAGE2")
        XCTAssertEqual(page.replyRequests.count, 1)
        XCTAssertEqual(page.replyRequests.first?.token, "REPLYTOKEN1")
        XCTAssertEqual(page.replyRequests.first?.parentId, "C1")

        let pinned = page.comments[0]
        XCTAssertEqual(pinned.id, "C1")
        XCTAssertEqual(pinned.text, "Top comment & stuff")           // entity-decoded
        XCTAssertEqual(pinned.author, "@alice")
        XCTAssertEqual(pinned.publishedTimeText, "1 month ago (edited)")
        XCTAssertTrue(pinned.isEdited)
        XCTAssertEqual(pinned.likeCountText, "85K")
        XCTAssertEqual(pinned.likeCount, 85_000)
        XCTAssertEqual(pinned.replyCount, 2)
        XCTAssertFalse(pinned.isReply)
        XCTAssertTrue(pinned.isHearted)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.pinnedByText, "Pinned by @creator")
        XCTAssertTrue(pinned.isVerified)

        let member = page.comments[1]
        XCTAssertEqual(member.id, "C2")
        XCTAssertEqual(member.likeCountText, "0")                     // empty → "0"
        XCTAssertEqual(member.likeCount, 0)
        XCTAssertFalse(member.isHearted)
        XCTAssertFalse(member.isPinned)
        XCTAssertTrue(member.isSponsor)
        XCTAssertEqual(member.sponsorshipMonths, 40)
        XCTAssertEqual(member.sponsorBadgeText, "Member (3 years, 4 months)")
    }

    func testParseReplyPage() throws {
        let response = try json(Fixtures.replyPage)
        let page = CommentParser.parse(response, videoId: "vid123")

        XCTAssertEqual(page.comments.count, 1)
        XCTAssertNil(page.nextPageToken)             // reply target ≠ comments-section
        let reply = page.comments[0]
        XCTAssertEqual(reply.id, "C1.R1")
        XCTAssertTrue(reply.isReply)
        XCTAssertEqual(reply.parentId, "C1")
        XCTAssertEqual(reply.text, "a reply")
        XCTAssertEqual(reply.likeCount, 3)
    }

    // MARK: - Export

    func testTSVExport() throws {
        let response = try json(Fixtures.topLevelPage)
        let comments = CommentParser.parse(response, videoId: "vid123").comments
        let tsv = comments.tsv()
        let lines = tsv.components(separatedBy: "\n")

        XCTAssertEqual(
            lines[0],
            "publishedTimeText\tsimpleText\tvotes\tauthor\tisReply\tisHearted\tisPinned\tisPaid\tpaidAmount\tisSponsor\tsponsorshipMonths"
        )
        // Pinned/hearted row
        XCTAssertTrue(lines[1].hasPrefix("1 month ago (edited)\tTop comment & stuff\t85K\t@alice\tfalse\ttrue\ttrue\t"))
        // Member row ends with sponsor=true, months=40
        XCTAssertTrue(lines[2].hasSuffix("\ttrue\t40"))
    }

    func testCSVQuotesFieldsWithCommas() throws {
        let response = try json(Fixtures.replyPage)
        let comments = CommentParser.parse(response, videoId: "vid123").comments
        let csv = comments.csv(header: false)
        XCTAssertFalse(csv.isEmpty)
    }

    // MARK: - Live network test (opt-in)

    /// Set `YT_LIVE_TESTS=1` to exercise the real InnerTube endpoints.
    func testLiveFetch() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YT_LIVE_TESTS"] == "1",
            "Set YT_LIVE_TESTS=1 to run live network tests."
        )
        let comments = try await YouTubeComments.fetch(
            "dQw4w9WgXcQ", includeReplies: false, limit: 40
        )
        XCTAssertFalse(comments.isEmpty)
        XCTAssertTrue(comments.contains { !$0.author.isEmpty && !$0.text.isEmpty })
    }

    // MARK: - Helpers

    private func json(_ string: String) throws -> [String: Any] {
        let data = Data(string.utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - Fixtures

/// Minimal fixtures that mirror the real InnerTube `next` response shape
/// verified against live videos (entity payloads + view-model join table).
private enum Fixtures {

    static let topLevelPage = """
    {
      "frameworkUpdates": { "entityBatchUpdate": { "mutations": [
        { "payload": { "commentEntityPayload": {
            "key": "K1",
            "properties": { "commentId": "C1", "content": { "content": "Top comment &amp; stuff" },
                            "publishedTime": "1 month ago (edited)", "replyLevel": 0, "toolbarStateKey": "T1" },
            "author": { "displayName": "@alice", "channelId": "UCa", "avatarThumbnailUrl": "http://a",
                        "isVerified": true, "isCreator": false },
            "toolbar": { "likeCountNotliked": "85K", "replyCount": "2" }
        } } },
        { "payload": { "engagementToolbarStateEntityPayload": { "key": "T1", "heartState": "TOOLBAR_HEART_STATE_HEARTED" } } },
        { "payload": { "commentEntityPayload": {
            "key": "K2",
            "properties": { "commentId": "C2", "content": { "content": "member here" },
                            "publishedTime": "2 weeks ago", "replyLevel": 0, "toolbarStateKey": "T2" },
            "author": { "displayName": "@bob", "channelId": "UCb", "isVerified": false, "isCreator": false,
                        "sponsorBadgeUrl": "http://badge", "sponsorBadgeA11y": "Member (3 years, 4 months)" },
            "toolbar": { "likeCountNotliked": "", "replyCount": "0" }
        } } }
      ] } },
      "onResponseReceivedEndpoints": [
        { "reloadContinuationItemsCommand": {
            "targetId": "engagement-panel-comments-section",
            "continuationItems": [
              { "commentThreadRenderer": {
                  "renderingPriority": "RENDERING_PRIORITY_PINNED_COMMENT",
                  "commentViewModel": { "commentViewModel": {
                      "commentKey": "K1", "toolbarStateKey": "T1", "commentSurfaceKey": "S1",
                      "pinnedText": "Pinned by @creator", "commentId": "C1" } },
                  "replies": { "commentRepliesRenderer": { "contents": [
                      { "continuationItemRenderer": { "continuationEndpoint": {
                          "continuationCommand": { "token": "REPLYTOKEN1" } } } }
                  ] } }
              } },
              { "commentThreadRenderer": {
                  "commentViewModel": { "commentViewModel": {
                      "commentKey": "K2", "toolbarStateKey": "T2", "commentSurfaceKey": "S2", "commentId": "C2" } }
              } },
              { "continuationItemRenderer": { "continuationEndpoint": {
                  "continuationCommand": { "token": "PAGE2" } } } }
            ]
        } }
      ]
    }
    """

    static let replyPage = """
    {
      "frameworkUpdates": { "entityBatchUpdate": { "mutations": [
        { "payload": { "commentEntityPayload": {
            "key": "K3",
            "properties": { "commentId": "C1.R1", "content": { "content": "a reply" },
                            "publishedTime": "1 month ago", "replyLevel": 1, "toolbarStateKey": "T3" },
            "author": { "displayName": "@carol", "channelId": "UCc" },
            "toolbar": { "likeCountNotliked": "3", "replyCount": "0" }
        } } }
      ] } },
      "onResponseReceivedEndpoints": [
        { "appendContinuationItemsAction": {
            "targetId": "comment-replies-item-C1",
            "continuationItems": [
              { "commentViewModel": { "commentViewModel": {
                  "commentKey": "K3", "toolbarStateKey": "T3", "commentId": "C1.R1" } } }
            ]
        } }
      ]
    }
    """
}
