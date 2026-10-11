// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-youtube-metadata",
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
        .library(
            name: "YouTubeSearch",
            targets: ["YouTubeSearch"]
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
        // Self-contained sibling target. Shares no code with the other modules
        // by design — searches YouTube site-wide or within one channel via the
        // InnerTube search surface.
        .target(
            name: "YouTubeSearch",
            dependencies: []
        ),
        .testTarget(
            name: "YouTubeSearchTests",
            dependencies: ["YouTubeSearch"]
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

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
