// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YouTubeTranscript",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "YouTubeTranscript",
            targets: ["YouTubeTranscript"]
        ),
        .library(
            name: "YouTubeComments",
            targets: ["YouTubeComments"]
        ),
        .library(
            name: "YouTubeChannel",
            targets: ["YouTubeChannel"]
        ),
    ],
    targets: [
        .target(
            name: "YouTubeTranscript",
            dependencies: []
        ),
        .testTarget(
            name: "YouTubeTranscriptTests",
            dependencies: ["YouTubeTranscript"]
        ),
        // Self-contained sibling target. Shares no code with YouTubeTranscript
        // by design — the two modules are independent parts of one package.
        .target(
            name: "YouTubeComments",
            dependencies: []
        ),
        .testTarget(
            name: "YouTubeCommentsTests",
            dependencies: ["YouTubeComments"]
        ),
        // Self-contained sibling target. Shares no code with the other modules
        // by design — enumerates a channel's uploads via the InnerTube browse API.
        .target(
            name: "YouTubeChannel",
            dependencies: []
        ),
        .testTarget(
            name: "YouTubeChannelTests",
            dependencies: ["YouTubeChannel"]
        ),
        // Example CLI that composes the three self-contained libraries into a
        // full channel → transcripts/comments dump. The libraries still share
        // no code; only this executable depends on all three.
        .executableTarget(
            name: "YouTubeDump",
            dependencies: ["YouTubeChannel", "YouTubeTranscript", "YouTubeComments"]
        ),
    ]
)
