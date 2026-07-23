//
//  YouTubeChannelTests.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import XCTest
@testable import YouTubeChannel

final class YouTubeChannelTests: XCTestCase {

    // MARK: - Channel URL normalisation

    func testNormaliseBareChannelId() throws {
        let url = try ChannelURL.url(from: "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw/videos?hl=en")
    }

    func testNormaliseHandle() throws {
        let url = try ChannelURL.url(from: "@GoogleDevelopers")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/@GoogleDevelopers/videos?hl=en")
    }

    func testNormaliseBareTokenTreatedAsHandle() throws {
        let url = try ChannelURL.url(from: "GoogleDevelopers")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/@GoogleDevelopers/videos?hl=en")
    }

    func testNormaliseChannelURL() throws {
        let url = try ChannelURL.url(from: "https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw/videos?hl=en")
    }

    func testNormaliseHandleURLWithExistingTabAndQuery() throws {
        let url = try ChannelURL.url(from: "https://www.youtube.com/@GoogleDevelopers/streams?view=0")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/@GoogleDevelopers/videos?hl=en")
    }

    func testNormaliseLegacyCustomURL() throws {
        let url = try ChannelURL.url(from: "https://www.youtube.com/c/GoogleDevelopers")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/c/GoogleDevelopers/videos?hl=en")
    }

    func testNormaliseLegacyUserURL() throws {
        let url = try ChannelURL.url(from: "youtube.com/user/GoogleDevelopers/videos")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/user/GoogleDevelopers/videos?hl=en")
    }

    func testNormaliseEmptyThrows() {
        XCTAssertThrowsError(try ChannelURL.url(from: "   ")) { error in
            XCTAssertEqual(error as? YouTubeChannelError, .invalidChannel)
        }
    }

    func testNormaliseNonYouTubeURLThrows() {
        XCTAssertThrowsError(try ChannelURL.url(from: "https://vimeo.com/channels/staffpicks"))
    }

    // MARK: - Parser (current lockupViewModel grid format)

    func testParseGridPageAndContinuation() throws {
        let json = Self.gridFixture(
            videoID: "JRArFxEfyQU",
            title: "How are large language models trained?",
            duration: "10:09",
            views: "4.7K views",
            published: "1 day ago",
            token: "CONTINUATION_TOKEN"
        )
        let page = ChannelParser.parse(json)

        XCTAssertEqual(page.videos.count, 1)
        let v = try XCTUnwrap(page.videos.first)
        XCTAssertEqual(v.id, "JRArFxEfyQU")
        XCTAssertEqual(v.title, "How are large language models trained?")
        XCTAssertEqual(v.lengthText, "10:09")
        XCTAssertEqual(v.viewCountText, "4.7K views")
        XCTAssertEqual(v.publishedText, "1 day ago")
        XCTAssertEqual(v.thumbnailUrl, "https://i.ytimg.com/vi/JRArFxEfyQU/hq720.jpg")
        XCTAssertEqual(page.nextToken, "CONTINUATION_TOKEN")
        XCTAssertEqual(v.url?.absoluteString, "https://youtu.be/JRArFxEfyQU")
    }

    /// A page whose only continuation token belongs to an unrelated section
    /// (the About panel) must not be mistaken for the grid's next-page token.
    func testParseIgnoresNonGridContinuationToken() throws {
        var json = Self.gridFixture(
            videoID: "abcdef12345",
            title: "Example",
            duration: "0:42",
            views: "10 views",
            published: "2 hours ago",
            token: nil // no grid token
        )
        // Bury an unrelated continuation somewhere else in the tree.
        json["aboutPanel"] = [
            "continuationItemRenderer": [
                "continuationEndpoint": ["continuationCommand": ["token": "ABOUT_TOKEN"]]
            ]
        ]
        let page = ChannelParser.parse(json)
        XCTAssertEqual(page.videos.count, 1)
        XCTAssertNil(page.nextToken, "Only the grid's sibling token should count as the next page")
    }

    func testParseDeduplicatesWithinPage() throws {
        // Two lockups with the same contentId → one video.
        let item = Self.lockupItem(
            videoID: "dup00000000", title: "Dup", duration: "1:00",
            views: "1 view", published: "now"
        )
        let json: [String: Any] = [
            "contents": ["richGridRenderer": ["contents": [item, item]]]
        ]
        let page = ChannelParser.parse(json)
        XCTAssertEqual(page.videos.count, 1)
    }

    func testParseEmptyGrid() {
        let page = ChannelParser.parse(["contents": [String: Any]()])
        XCTAssertTrue(page.videos.isEmpty)
        XCTAssertNil(page.nextToken)
    }

    // MARK: - Shorts

    func testParseShortsLockup() throws {
        let short: [String: Any] = [
            "richItemRenderer": [
                "content": [
                    "shortsLockupViewModel": [
                        "onTap": ["innertubeCommand": ["reelWatchEndpoint": ["videoId": "Df5Y-2ndQyU"]]],
                        "overlayMetadata": [
                            "primaryText": ["content": "Read My Book, You Could Win $1,000,000"],
                            "secondaryText": ["content": "6.5M views"]
                        ],
                        "thumbnailViewModel": [
                            "image": ["sources": [["url": "https://i.ytimg.com/vi/Df5Y-2ndQyU/frame0.jpg", "width": 1080, "height": 1920]]]
                        ]
                    ]
                ]
            ]
        ]
        let json: [String: Any] = ["contents": ["richGridRenderer": ["contents": [short]]]]
        let page = ChannelParser.parse(json)

        let v = try XCTUnwrap(page.videos.first)
        XCTAssertEqual(v.id, "Df5Y-2ndQyU")
        XCTAssertEqual(v.title, "Read My Book, You Could Win $1,000,000")
        XCTAssertEqual(v.viewCountText, "6.5M views")
        XCTAssertTrue(v.isShort)
        XCTAssertNil(v.lengthText)
    }

    // MARK: - Badges

    func testParseLiveBadge() throws {
        var item = Self.lockupItem(videoID: "live0000000", title: "Live now", duration: "0:00", views: "1 watching", published: "")
        // Inject a LIVE badge alongside the duration badge.
        if var rir = item["richItemRenderer"] as? [String: Any],
           var content = rir["content"] as? [String: Any],
           var lockup = content["lockupViewModel"] as? [String: Any],
           var image = lockup["contentImage"] as? [String: Any],
           var tvm = image["thumbnailViewModel"] as? [String: Any] {
            tvm["overlays"] = [[
                "thumbnailBottomOverlayViewModel": [
                    "badges": [["thumbnailBadgeViewModel": ["text": "LIVE", "badgeStyle": "THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE"]]]
                ]
            ]]
            image["thumbnailViewModel"] = tvm
            lockup["contentImage"] = image
            content["lockupViewModel"] = lockup
            rir["content"] = content
            item["richItemRenderer"] = rir
        }
        let json: [String: Any] = ["contents": ["richGridRenderer": ["contents": [item]]]]
        let v = try XCTUnwrap(ChannelParser.parse(json).videos.first)
        XCTAssertTrue(v.isLive)
    }

    // MARK: - Channel info

    func testParseChannelInfo() throws {
        let json: [String: Any] = [
            "metadata": [
                "channelMetadataRenderer": [
                    "title": "Google for Developers",
                    "externalId": "UC_x5XG1OV2P6uZZ5FSM9Ttw",
                    "description": "Subscribe to join a community…",
                    "vanityChannelUrl": "http://www.youtube.com/@GoogleDevelopers",
                    "keywords": "\"google developers\"",
                    "isFamilySafe": true,
                    "avatar": ["thumbnails": [["url": "https://yt3.example/s88", "width": 88], ["url": "https://yt3.example/s900", "width": 900]]]
                ]
            ],
            "header": [
                "pageHeaderViewModel": [
                    "metadata": ["contentMetadataViewModel": ["metadataRows": [
                        ["metadataParts": [["text": ["content": "@GoogleDevelopers"]]]],
                        ["metadataParts": [["text": ["content": "2.66M subscribers"]], ["text": ["content": "6K videos"]]]]
                    ]]]
                ]
            ]
        ]
        let info = try XCTUnwrap(ChannelParser.parseChannelInfo(json))
        XCTAssertEqual(info.channelId, "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertEqual(info.title, "Google for Developers")
        XCTAssertEqual(info.handle, "@GoogleDevelopers")
        XCTAssertEqual(info.subscriberText, "2.66M subscribers")
        XCTAssertEqual(info.videoCountText, "6K videos")
        XCTAssertEqual(info.avatarUrl, "https://yt3.example/s900")
        XCTAssertEqual(info.isFamilySafe, true)
    }

    // MARK: - Video details

    func testVideoDetailsParser() throws {
        let json: [String: Any] = [
            "videoDetails": [
                "videoId": "iYlODtkyw_I",
                "title": "Survive 30 Days Chained To A Stranger, Win $250,000",
                "viewCount": "77925146",
                "lengthSeconds": "2104",
                "shortDescription": "imagine being chained…",
                "author": "MrBeast",
                "channelId": "UCX6OQ3DkcsbYNE6H8uQQuVA",
                "isLiveContent": false
            ],
            "microformat": ["playerMicroformatRenderer": [
                "publishDate": "2026-06-27T09:00:05-07:00",
                "uploadDate": "2026-06-27T09:00:05-07:00",
                "category": "Entertainment"
            ]]
        ]
        let d = try XCTUnwrap(VideoDetailsParser.parse(json, videoId: "iYlODtkyw_I"))
        XCTAssertEqual(d.viewCount, 77_925_146)
        XCTAssertEqual(d.lengthSeconds, 2104)
        XCTAssertEqual(d.publishDate, "2026-06-27T09:00:05-07:00")
        XCTAssertEqual(d.category, "Entertainment")
        XCTAssertEqual(d.channelId, "UCX6OQ3DkcsbYNE6H8uQQuVA")
    }

    func testVideoDetailsParserMissingDetailsReturnsNil() {
        XCTAssertNil(VideoDetailsParser.parse(["playabilityStatus": ["status": "ERROR"]], videoId: "x"))
    }

    // MARK: - Video ID extraction

    func testVideoIDFromURL() throws {
        XCTAssertEqual(try VideoID.extract(from: "https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(try VideoID.extract(from: "dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    // MARK: - Fixtures

    /// Builds a single `richItemRenderer` grid item in YouTube's current
    /// `lockupViewModel` shape.
    static func lockupItem(
        videoID: String,
        title: String,
        duration: String,
        views: String,
        published: String
    ) -> [String: Any] {
        [
            "richItemRenderer": [
                "content": [
                    "lockupViewModel": [
                        "contentId": videoID,
                        "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                        "contentImage": [
                            "thumbnailViewModel": [
                                "image": [
                                    "sources": [
                                        ["url": "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg", "width": 168, "height": 94],
                                        ["url": "https://i.ytimg.com/vi/\(videoID)/hq720.jpg", "width": 360, "height": 202]
                                    ]
                                ],
                                "overlays": [
                                    [
                                        "thumbnailBottomOverlayViewModel": [
                                            "badges": [
                                                ["thumbnailBadgeViewModel": ["text": duration, "badgeStyle": "THUMBNAIL_OVERLAY_BADGE_STYLE_DEFAULT"]]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ],
                        "metadata": [
                            "lockupMetadataViewModel": [
                                "title": ["content": title],
                                "metadata": [
                                    "contentMetadataViewModel": [
                                        "metadataRows": [
                                            ["metadataParts": [
                                                ["text": ["content": views]],
                                                ["text": ["content": published]]
                                            ]]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    /// Wraps a lockup item in a `richGridRenderer`, optionally with a sibling
    /// grid continuation token.
    static func gridFixture(
        videoID: String,
        title: String,
        duration: String,
        views: String,
        published: String,
        token: String?
    ) -> [String: Any] {
        var contents: [Any] = [
            lockupItem(videoID: videoID, title: title, duration: duration, views: views, published: published)
        ]
        if let token {
            contents.append([
                "continuationItemRenderer": [
                    "continuationEndpoint": ["continuationCommand": ["token": token]]
                ]
            ])
        }
        return ["contents": ["richGridRenderer": ["contents": contents]]]
    }
}
