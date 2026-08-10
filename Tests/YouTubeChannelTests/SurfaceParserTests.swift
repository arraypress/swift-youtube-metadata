//
//  SurfaceParserTests.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2026.
//
//  Fixtures mirror the shapes observed on live pages in 2026: playlists and
//  videos share `lockupViewModel` and differ only by `contentType`, and a post's
//  gallery uses a different renderer from a single image.
//

import XCTest
@testable import YouTubeChannel

final class SurfaceParserTests: XCTestCase {

    // MARK: - Fixtures

    private func lockup(type: String, id: String, title: String, rows: [String] = []) -> [String: Any] {
        [
            "lockupViewModel": [
                "contentType": type,
                "contentId": id,
                "metadata": [
                    "lockupMetadataViewModel": [
                        "title": ["content": title],
                        "metadata": [
                            "contentMetadataViewModel": [
                                "metadataRows": [
                                    ["metadataParts": rows.map { ["text": ["content": $0]] }]
                                ]
                            ]
                        ],
                    ]
                ],
                "contentImage": [
                    "collectionThumbnailViewModel": [
                        "primaryThumbnail": [
                            "thumbnailViewModel": [
                                "image": ["sources": [
                                    ["url": "https://i.ytimg.com/small.jpg", "width": 168],
                                    ["url": "https://i.ytimg.com/large.jpg", "width": 720],
                                ]]
                            ]
                        ]
                    ]
                ],
            ]
        ]
    }

    private func wrap(_ items: [[String: Any]], token: String? = nil) -> [String: Any] {
        var contents: [Any] = items.map { ["richItemRenderer": ["content": $0]] }
        if let token {
            contents.append([
                "continuationItemRenderer": [
                    "continuationEndpoint": ["continuationCommand": ["token": token]]
                ]
            ])
        }
        return ["contents": ["richGridRenderer": ["contents": contents]]]
    }

    // MARK: - Playlists

    func testPlaylistsTabParsesIdTitleAndCount() {
        let root = wrap([
            lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "Interviews", rows: ["20 videos"])
        ])

        let page = SurfaceParser.playlists(root)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "PLabc")
        XCTAssertEqual(page.items[0].title, "Interviews")
        XCTAssertEqual(page.items[0].videoCountText, "20 videos")
        XCTAssertEqual(page.items[0].url?.absoluteString, "https://www.youtube.com/playlist?list=PLabc")
    }

    func testPlaylistsIgnoreVideoLockups() {
        // Playlists and videos share one renderer. Without the contentType guard
        // a video would be returned as a playlist whose "id" is a video id.
        let root = wrap([
            lockup(type: "LOCKUP_CONTENT_TYPE_VIDEO", id: "dQw4w9WgXcQ", title: "A video"),
            lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "A playlist"),
        ])

        let page = SurfaceParser.playlists(root)
        XCTAssertEqual(page.items.map(\.id), ["PLabc"])
    }

    func testPlaylistThumbnailPicksTheWidestSource() {
        let root = wrap([lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "T")])
        XCTAssertEqual(SurfaceParser.playlists(root).items[0].thumbnailUrl, "https://i.ytimg.com/large.jpg")
    }

    func testPlaylistsDeduplicate() {
        let root = wrap([
            lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "One"),
            lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "One again"),
        ])
        XCTAssertEqual(SurfaceParser.playlists(root).items.count, 1)
    }

    func testContinuationTokenIsPickedUp() {
        let root = wrap([lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "T")], token: "NEXT")
        XCTAssertEqual(SurfaceParser.playlists(root).nextToken, "NEXT")
    }

    func testNoContinuationWhenTheSurfaceIsExhausted() {
        let root = wrap([lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLabc", title: "T")])
        XCTAssertNil(SurfaceParser.playlists(root).nextToken)
    }

    // MARK: - Playlist Contents

    func testPlaylistContentsParseVideoLockups() {
        // playlistVideoRenderer is gone; entries are the same lockup the channel
        // grid uses, so this must reuse the grid's parser rather than a copy.
        let root = wrap([
            lockup(type: "LOCKUP_CONTENT_TYPE_VIDEO", id: "abc12345678", title: "Ep 1"),
            lockup(type: "LOCKUP_CONTENT_TYPE_PLAYLIST", id: "PLnested", title: "Not a video"),
        ])

        let page = SurfaceParser.playlistVideos(root)
        XCTAssertEqual(page.items.map(\.id), ["abc12345678"])
        XCTAssertEqual(page.items[0].title, "Ep 1")
    }

    // MARK: - Posts

    private func post(
        id: String,
        text: String = "Hello",
        published: String = "12 days ago",
        likes: String = "277",
        attachment: [String: Any]? = nil
    ) -> [String: Any] {
        var renderer: [String: Any] = [
            "postId": id,
            "authorText": ["runs": [["text": "Jona Marie"]]],
            "contentText": ["runs": [["text": text]]],
            "publishedTimeText": ["runs": [["text": published]]],
            "voteCount": ["simpleText": likes],
        ]
        if let attachment { renderer["backstageAttachment"] = attachment }
        return ["backstagePostThreadRenderer": ["post": ["backstagePostRenderer": renderer]]]
    }

    private func image(_ url: String) -> [String: Any] {
        ["backstageImageRenderer": ["image": ["thumbnails": [["url": url, "width": 1080]]]]]
    }

    func testPostParsesCoreFields() {
        let root = ["contents": [post(id: "UgkxABC")]]
        let page = SurfaceParser.posts(root)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "UgkxABC")
        XCTAssertEqual(page.items[0].author, "Jona Marie")
        XCTAssertEqual(page.items[0].text, "Hello")
        XCTAssertEqual(page.items[0].likeCountText, "277")
        XCTAssertEqual(page.items[0].url?.absoluteString, "https://www.youtube.com/post/UgkxABC")
    }

    func testEditedMarkerIsLiftedOutOfTheTimestamp() {
        // Leaving "(edited)" in the timestamp *and* setting the flag makes every
        // consumer report it twice.
        let root = ["contents": [post(id: "A", published: "2 weeks ago (edited)")]]
        let parsed = SurfaceParser.posts(root).items[0]

        XCTAssertTrue(parsed.isEdited)
        XCTAssertEqual(parsed.publishedText, "2 weeks ago")
    }

    func testUneditedPostKeepsItsTimestampIntact() {
        let root = ["contents": [post(id: "A", published: "12 days ago")]]
        let parsed = SurfaceParser.posts(root).items[0]
        XCTAssertFalse(parsed.isEdited)
        XCTAssertEqual(parsed.publishedText, "12 days ago")
    }

    func testSingleImageAttachment() {
        let root = ["contents": [post(id: "A", attachment: image("https://img/1.jpg"))]]
        let attachment = SurfaceParser.posts(root).items[0].attachment

        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.imageUrls, ["https://img/1.jpg"])
    }

    func testGalleryKeepsEveryImage() {
        // A gallery contains individual image renderers too, so recognising the
        // single-image case first would collapse six photos down to one.
        let gallery: [String: Any] = [
            "postMultiImageRenderer": [
                "images": [image("https://img/1.jpg"), image("https://img/2.jpg"), image("https://img/3.jpg")]
            ]
        ]
        let root = ["contents": [post(id: "A", attachment: gallery)]]
        let attachment = SurfaceParser.posts(root).items[0].attachment

        XCTAssertEqual(attachment.kind, .gallery)
        XCTAssertEqual(attachment.imageUrls.count, 3)
    }

    func testVideoAttachment() {
        let video: [String: Any] = [
            "videoRenderer": ["videoId": "abc12345678", "title": ["runs": [["text": "My vlog"]]]]
        ]
        let root = ["contents": [post(id: "A", attachment: video)]]
        let attachment = SurfaceParser.posts(root).items[0].attachment

        XCTAssertEqual(attachment.kind, .video)
        XCTAssertEqual(attachment.videoId, "abc12345678")
        XCTAssertEqual(attachment.videoTitle, "My vlog")
    }

    func testPollAttachment() {
        let poll: [String: Any] = [
            "pollRenderer": ["choices": [
                ["text": ["runs": [["text": "Yes"]]]],
                ["text": ["runs": [["text": "No"]]]],
            ]]
        ]
        let root = ["contents": [post(id: "A", attachment: poll)]]
        let attachment = SurfaceParser.posts(root).items[0].attachment

        XCTAssertEqual(attachment.kind, .poll)
        XCTAssertEqual(attachment.pollOptions, ["Yes", "No"])
    }

    func testPostWithNoAttachment() {
        let root = ["contents": [post(id: "A")]]
        XCTAssertEqual(SurfaceParser.posts(root).items[0].attachment.kind, .none)
        XCTAssertTrue(SurfaceParser.posts(root).items[0].attachment.imageUrls.isEmpty)
    }

    func testPostsDeduplicateById() {
        let root = ["contents": [post(id: "A"), post(id: "A"), post(id: "B")]]
        XCTAssertEqual(SurfaceParser.posts(root).items.map(\.id), ["A", "B"])
    }

    func testMultilinePostTextIsPreserved() {
        let renderer: [String: Any] = [
            "backstagePostRenderer": [
                "postId": "A",
                "contentText": ["runs": [["text": "line one\n\nline two"]]],
            ]
        ]
        let parsed = SurfaceParser.posts(["contents": [renderer]]).items[0]
        XCTAssertEqual(parsed.text, "line one\n\nline two")
    }

    // MARK: - URLs

    func testChannelSurfaceURLs() throws {
        XCTAssertEqual(
            try ChannelURL.url(from: "@iJustine", surface: .playlists).absoluteString,
            "https://www.youtube.com/@iJustine/playlists?hl=en"
        )
        XCTAssertEqual(
            try ChannelURL.url(from: "@iJustine", surface: .posts).absoluteString,
            "https://www.youtube.com/@iJustine/posts?hl=en"
        )
    }

    func testSurfaceURLStripsAnExistingTab() throws {
        XCTAssertEqual(
            try ChannelURL.url(from: "https://www.youtube.com/@iJustine/videos", surface: .posts).absoluteString,
            "https://www.youtube.com/@iJustine/posts?hl=en"
        )
    }

    func testPlaylistURLFromBareID() throws {
        XCTAssertEqual(
            try ChannelURL.playlistURL(from: "PLabc123").absoluteString,
            "https://www.youtube.com/playlist?list=PLabc123&hl=en"
        )
    }

    func testPlaylistURLFromFullURL() throws {
        XCTAssertEqual(
            try ChannelURL.playlistURL(from: "https://www.youtube.com/playlist?list=PLxyz&index=2").absoluteString,
            "https://www.youtube.com/playlist?list=PLxyz&hl=en"
        )
    }

    func testPlaylistURLAcceptsNonPLPrefixes() throws {
        // Uploads feeds are UU…, mixes RD…, likes LL… — the prefix is not a
        // validity test.
        for id in ["UUabc123", "RDabc123", "LLabc123"] {
            XCTAssertNoThrow(try ChannelURL.playlistURL(from: id))
        }
    }

    func testPlaylistURLRejectsGarbage() {
        XCTAssertThrowsError(try ChannelURL.playlistURL(from: ""))
        XCTAssertThrowsError(try ChannelURL.playlistURL(from: "not a playlist!"))
    }
}
