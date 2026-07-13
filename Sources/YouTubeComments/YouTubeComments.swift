//
//  YouTubeComments.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Download public comments from a YouTube video.
///
/// Uses YouTube's internal InnerTube API (the same endpoints the website's
/// comment section calls) to page through comments with **no API key, no
/// quota, and no authentication**. This exposes data the official YouTube Data
/// API does not — creator hearts, pinned status, membership badges, and paid
/// "Super Thanks" chips.
///
/// ## Quick Start
///
/// ```swift
/// import YouTubeComments
///
/// // Fetch everything (top-level comments + replies), newest ranking:
/// let comments = try await YouTubeComments.fetch("dQw4w9WgXcQ")
///
/// // Just the first 200, "Newest first", no replies:
/// let recent = try await YouTubeComments.fetch(
///     "https://youtu.be/dQw4w9WgXcQ",
///     sortBy: .newest,
///     includeReplies: false,
///     limit: 200
/// )
///
/// // Stream them as they arrive (memory-friendly for huge threads):
/// for try await comment in YouTubeComments.stream("dQw4w9WgXcQ") {
///     print("\(comment.author): \(comment.text)")
/// }
///
/// // Export to your spreadsheet format:
/// let tsv = comments.tsv()
/// ```
///
/// ## How It Works
///
/// 1. Fetches the watch page to get the InnerTube API key, client version, and
///    the comment section's first continuation token.
/// 2. POSTs to `youtubei/v1/next` with that token to get a page of comments
///    plus the token for the next page.
/// 3. Repeats until there are no more pages; for each top-level comment it
///    follows the reply continuation so threads stay intact.
///
/// - Note: This relies on undocumented endpoints that can change, and it is
///   against YouTube's Terms of Service. Use responsibly and expect to hit
///   ``YouTubeCommentsError/ipBlocked`` if you fetch too aggressively.
public enum YouTubeComments {

    // MARK: - Configuration

    /// Tunables for networking, politeness, and rate-limit handling.
    public struct Configuration: Sendable {

        /// A custom `URLSession` to use. When `nil`, the client builds its own
        /// session with an isolated cookie store and the timeouts below.
        public var session: URLSession?

        /// Per-request timeout in seconds.
        public var requestTimeout: TimeInterval

        /// Whole-resource timeout in seconds.
        public var resourceTimeout: TimeInterval

        /// Maximum retries on `429`/`503`/transient network errors.
        public var maxRetries: Int

        /// Base backoff (seconds) for the first retry; doubles each attempt.
        public var baseBackoff: Double

        /// Ceiling for a single backoff wait, in seconds.
        public var maxBackoff: Double

        /// Politeness delay inserted between page requests, in seconds.
        ///
        /// A small delay dramatically lowers the chance of being rate-limited
        /// on large threads. Defaults to `0.1`.
        public var pageDelay: Double

        public init(
            session: URLSession? = nil,
            requestTimeout: TimeInterval = 15,
            resourceTimeout: TimeInterval = 30,
            maxRetries: Int = 3,
            baseBackoff: Double = 1.0,
            maxBackoff: Double = 30.0,
            pageDelay: Double = 0.1
        ) {
            self.session = session
            self.requestTimeout = requestTimeout
            self.resourceTimeout = resourceTimeout
            self.maxRetries = maxRetries
            self.baseBackoff = baseBackoff
            self.maxBackoff = maxBackoff
            self.pageDelay = pageDelay
        }

        public static let `default` = Configuration()
    }

    // MARK: - Public API

    /// Fetches comments for a video and returns them as an array.
    ///
    /// - Parameters:
    ///   - input: A YouTube video ID or any supported YouTube URL.
    ///   - sortBy: Comment ordering. Defaults to ``CommentSort/top``.
    ///   - includeReplies: When `true` (default), replies are fetched and
    ///     emitted immediately after their parent so thread order is preserved.
    ///   - limit: Optional cap on the total number of comments returned.
    ///   - configuration: Networking/politeness options.
    /// - Returns: The collected comments (top-level and, if requested, replies).
    /// - Throws: ``YouTubeCommentsError`` on failure.
    public static func fetch(
        _ input: String,
        sortBy: CommentSort = .top,
        includeReplies: Bool = true,
        limit: Int? = nil,
        configuration: Configuration = .default
    ) async throws -> [Comment] {
        var result: [Comment] = []
        for try await comment in stream(
            input, sortBy: sortBy, includeReplies: includeReplies, configuration: configuration
        ) {
            result.append(comment)
            if let limit, result.count >= limit { break }
        }
        return result
    }

    /// Streams comments for a video as they are fetched.
    ///
    /// Ideal for large threads: comments are yielded page-by-page instead of
    /// being buffered. Breaking out of the loop cancels the underlying work.
    ///
    /// ```swift
    /// for try await comment in YouTubeComments.stream(videoId) {
    ///     if comment.isHearted { print("❤️ \(comment.text)") }
    /// }
    /// ```
    public static func stream(
        _ input: String,
        sortBy: CommentSort = .top,
        includeReplies: Bool = true,
        configuration: Configuration = .default
    ) -> AsyncThrowingStream<Comment, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let videoId = try VideoID.extract(from: input)
                    try await run(
                        videoId: videoId,
                        sortBy: sortBy,
                        includeReplies: includeReplies,
                        configuration: configuration
                    ) { comment in
                        continuation.yield(comment)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Engine

    private static func run(
        videoId: String,
        sortBy: CommentSort,
        includeReplies: Bool,
        configuration: Configuration,
        emit: (Comment) -> Void
    ) async throws {
        let client = InnerTubeClient(config: configuration)
        let boot = try await client.bootstrap(videoId: videoId)

        // First page (the bootstrap token is the "Top" ordering).
        var response = try await client.next(
            token: boot.continuationToken, apiKey: boot.apiKey, clientVersion: boot.clientVersion
        )

        // Switch ordering if the caller asked for something other than Top.
        if sortBy != .top, let sortToken = sortToken(in: response, index: sortBy.menuIndex) {
            try await delay(configuration)
            response = try await client.next(
                token: sortToken, apiKey: boot.apiKey, clientVersion: boot.clientVersion
            )
        }

        var current: [String: Any]? = response
        while let resp = current {
            try Task.checkCancellation()
            let page = CommentParser.parse(resp, videoId: videoId)
            let replyTokens = Dictionary(
                page.replyRequests.map { ($0.parentId, $0.token) },
                uniquingKeysWith: { first, _ in first }
            )

            for comment in page.comments {
                emit(comment)
                if includeReplies, !comment.isReply, let token = replyTokens[comment.id] {
                    try await emitReplies(
                        startToken: token, client: client, boot: boot,
                        videoId: videoId, configuration: configuration, emit: emit
                    )
                }
            }

            guard let nextToken = page.nextPageToken else { break }
            try await delay(configuration)
            current = try await client.next(
                token: nextToken, apiKey: boot.apiKey, clientVersion: boot.clientVersion
            )
        }
    }

    /// Follows a thread's reply continuation (and any "show more replies"),
    /// emitting each reply.
    private static func emitReplies(
        startToken: String,
        client: InnerTubeClient,
        boot: InnerTubeClient.Bootstrap,
        videoId: String,
        configuration: Configuration,
        emit: (Comment) -> Void
    ) async throws {
        var token: String? = startToken
        while let current = token {
            try Task.checkCancellation()
            try await delay(configuration)
            let resp = try await client.next(
                token: current, apiKey: boot.apiKey, clientVersion: boot.clientVersion
            )
            let page = CommentParser.parse(resp, videoId: videoId)
            for reply in page.comments { emit(reply) }
            // A reply response's continuation (if any) is a "show more replies".
            token = page.replyRequests.first?.token
        }
    }

    // MARK: - Helpers

    /// Extracts the continuation token for a given sort-menu index from a
    /// response's `sortFilterSubMenuRenderer`.
    private static func sortToken(in response: [String: Any], index: Int) -> String? {
        let menu = JSONNav.first("sortFilterSubMenuRenderer", in: response)
        guard let items = JSONNav.first("subMenuItems", in: menu) as? [Any],
              index < items.count else { return nil }
        return JSONNav.string("token", in: items[index])
    }

    private static func delay(_ configuration: Configuration) async throws {
        guard configuration.pageDelay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(configuration.pageDelay * 1_000_000_000))
    }
}
