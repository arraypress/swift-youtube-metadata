//
//  YouTubeChannel.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Enumerate every public upload on a YouTube channel.
///
/// Uses YouTube's internal InnerTube `browse` API (the same endpoint the
/// website's channel grid calls) to page through a channel's Videos tab with
/// **no API key, no quota, and no authentication**. It returns the full upload
/// history — not just the ~15 most recent that the public RSS feed exposes.
///
/// Pair it with the sibling modules to pull a whole channel's data:
///
/// ```swift
/// import YouTubeChannel
/// import YouTubeTranscript
/// import YouTubeComments
///
/// let videos = try await YouTubeChannel.videos("@GoogleDevelopers")
/// for video in videos {
///     let transcript = try? await YouTubeTranscript.fetch(video.id)
///     let comments    = try? await YouTubeComments.fetch(video.id, limit: 500)
///     // …persist as you go…
/// }
/// ```
///
/// ## Quick Start
///
/// ```swift
/// // Just the video IDs (lightest):
/// let ids = try await YouTubeChannel.videoIDs("UC_x5XG1OV2P6uZZ5FSM9Ttw")
///
/// // Videos with title / length / views / published / thumbnail:
/// let videos = try await YouTubeChannel.videos("@GoogleDevelopers", limit: 200)
///
/// // Stream them as each page arrives (memory-friendly for huge channels):
/// for try await video in YouTubeChannel.stream("https://youtube.com/@GoogleDevelopers") {
///     print("\(video.id)  \(video.title)")
/// }
/// ```
///
/// ## Accepted inputs
///
/// Channel IDs (`"UC…"`), handles (`"@name"` or a bare `"name"`), and channel
/// URLs (`/channel/UC…`, `/@handle`, `/c/name`, `/user/name`).
///
/// ## How It Works
///
/// 1. Fetches the channel's Videos tab to get the InnerTube API key, client
///    version, the first page of uploads, and the grid continuation token.
/// 2. POSTs to `youtubei/v1/browse` with that token to get the next page plus
///    the token after it.
/// 3. Repeats until the grid is exhausted.
///
/// - Note: This relies on undocumented endpoints that can change, and it is
///   against YouTube's Terms of Service. Enumerating a large channel and then
///   fetching per-video data means many requests — keep ``Configuration/pageDelay``
///   non-zero and expect ``YouTubeChannelError/ipBlocked`` if you fetch too
///   aggressively.
public enum YouTubeChannel {

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
        /// A small delay dramatically lowers the chance of being rate-limited on
        /// large channels. Defaults to `0.2`.
        public var pageDelay: Double

        /// Maximum number of concurrent `player` requests when enriching many
        /// videos via ``YouTubeChannel/detailsStream(for:configuration:)``.
        ///
        /// Kept low by default to stay under YouTube's rate limits on
        /// channel-wide scrapes. Defaults to `4`.
        public var maxConcurrentDetails: Int

        public init(
            session: URLSession? = nil,
            requestTimeout: TimeInterval = 15,
            resourceTimeout: TimeInterval = 30,
            maxRetries: Int = 3,
            baseBackoff: Double = 1.0,
            maxBackoff: Double = 30.0,
            pageDelay: Double = 0.2,
            maxConcurrentDetails: Int = 4
        ) {
            self.session = session
            self.requestTimeout = requestTimeout
            self.resourceTimeout = resourceTimeout
            self.maxRetries = maxRetries
            self.baseBackoff = baseBackoff
            self.maxBackoff = maxBackoff
            self.pageDelay = pageDelay
            self.maxConcurrentDetails = max(1, maxConcurrentDetails)
        }

        public static let `default` = Configuration()
    }

    // MARK: - Public API

    /// Returns the video IDs for every item on a channel tab.
    ///
    /// - Parameters:
    ///   - input: A channel ID, handle, or channel URL.
    ///   - tab: Which tab to enumerate. Defaults to ``ContentTab/videos``.
    ///   - limit: Optional cap on the number of IDs returned.
    ///   - configuration: Networking/politeness options.
    /// - Returns: The video IDs in the channel's grid order (newest first).
    /// - Throws: ``YouTubeChannelError`` on failure.
    public static func videoIDs(
        _ input: String,
        tab: ContentTab = .videos,
        limit: Int? = nil,
        configuration: Configuration = .default
    ) async throws -> [String] {
        try await videos(input, tab: tab, limit: limit, configuration: configuration).map(\.id)
    }

    /// Returns every item on a channel tab with its grid metadata.
    ///
    /// - Parameters:
    ///   - input: A channel ID, handle, or channel URL.
    ///   - tab: Which tab to enumerate. Defaults to ``ContentTab/videos``.
    ///   - limit: Optional cap on the number of items returned.
    ///   - configuration: Networking/politeness options.
    /// - Returns: The items in the channel's grid order (newest first).
    /// - Throws: ``YouTubeChannelError`` on failure.
    public static func videos(
        _ input: String,
        tab: ContentTab = .videos,
        limit: Int? = nil,
        configuration: Configuration = .default
    ) async throws -> [ChannelVideo] {
        var result: [ChannelVideo] = []
        for try await video in stream(input, tab: tab, configuration: configuration) {
            result.append(video)
            if let limit, result.count >= limit { break }
        }
        return result
    }

    /// Streams a channel tab's items as each page is fetched.
    ///
    /// Ideal for large channels: items are yielded page-by-page instead of being
    /// buffered. Breaking out of the loop cancels the underlying work.
    ///
    /// ```swift
    /// for try await video in YouTubeChannel.stream("@GoogleDevelopers") {
    ///     print(video.title)
    /// }
    /// ```
    public static func stream(
        _ input: String,
        tab: ContentTab = .videos,
        configuration: Configuration = .default
    ) -> AsyncThrowingStream<ChannelVideo, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(input: input, tab: tab, configuration: configuration) { video in
                        continuation.yield(video)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Fetches channel-level metadata (title, handle, subscriber text, avatar,
    /// description, …) with a single page load — no video enumeration.
    ///
    /// ```swift
    /// let info = try await YouTubeChannel.info("@MrBeast")
    /// print(info.title, info.subscriberText ?? "")
    /// ```
    ///
    /// - Throws: ``YouTubeChannelError`` on failure.
    public static func info(
        _ input: String,
        configuration: Configuration = .default
    ) async throws -> ChannelInfo {
        let url = try ChannelURL.url(from: input, tab: .videos)
        let client = InnerTubeBrowseClient(config: configuration)
        let boot = try await client.bootstrap(url: url, channel: input)
        guard let channelInfo = boot.channelInfo else {
            throw YouTubeChannelError.channelUnavailable(channel: input)
        }
        return channelInfo
    }

    /// Fetches exact statistics for a single video — precise view count, length
    /// in seconds, publish date, full description, category, and keywords — with
    /// one `player` request.
    ///
    /// This is the Tier-2 data the channel grid does not carry. For a whole
    /// channel, page IDs with ``videoIDs(_:tab:limit:configuration:)`` and call
    /// this per ID (mind the rate limit — keep ``Configuration/pageDelay``
    /// non-zero and consider a concurrency cap).
    ///
    /// - Parameter input: A video ID or any supported YouTube video URL.
    /// - Throws: ``YouTubeChannelError`` on failure.
    public static func details(
        for input: String,
        configuration: Configuration = .default
    ) async throws -> VideoDetails {
        let videoId = try VideoID.extract(from: input)
        // The player endpoint needs an InnerTube key + client version. Bootstrap
        // off the video's watch page to read them live.
        let client = InnerTubeBrowseClient(config: configuration)
        let (apiKey, clientVersion) = try await client.watchPageCredentials(videoId: videoId)
        return try await client.player(videoId: videoId, apiKey: apiKey, clientVersion: clientVersion)
    }

    /// Fetches exact statistics for many videos, reusing one set of InnerTube
    /// credentials across the whole batch and capping concurrency.
    ///
    /// Unlike calling ``details(for:configuration:)`` in a loop — which
    /// re-reads a watch page for every video (two requests each) — this reads
    /// credentials **once** and then issues one `player` request per video, at
    /// most ``Configuration/maxConcurrentDetails`` in flight with
    /// ``Configuration/pageDelay`` spacing.
    ///
    /// ```swift
    /// let ids = try await YouTubeChannel.videoIDs("@GoogleDevelopers")
    /// for try await details in YouTubeChannel.detailsStream(for: ids) {
    ///     print(details.id, details.viewCount ?? -1)
    /// }
    /// ```
    ///
    /// Results are yielded **as they complete**, so their order does not match
    /// the input. Videos that individually fail (removed, private, parse error)
    /// are skipped rather than aborting the batch — diff the yielded ``VideoDetails/id``s
    /// against your input to find gaps. A rate-limit (``YouTubeChannelError/ipBlocked``
    /// / ``YouTubeChannelError/requestBlocked``) is terminal and finishes the
    /// stream with that error, since continuing would be futile.
    ///
    /// - Parameters:
    ///   - ids: Video IDs or YouTube video URLs.
    ///   - configuration: Networking/politeness options.
    public static func detailsStream(
        for ids: [String],
        configuration: Configuration = .default
    ) -> AsyncThrowingStream<VideoDetails, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Normalise inputs up front; skip anything unparseable.
                    let videoIds = ids.compactMap { try? VideoID.extract(from: $0) }
                    guard let seed = videoIds.first else { continuation.finish(); return }

                    let client = InnerTubeBrowseClient(config: configuration)
                    let (apiKey, clientVersion) = try await client.watchPageCredentials(videoId: seed)

                    try await withThrowingTaskGroup(of: VideoDetails?.self) { group in
                        var next = 0
                        let inFlightCap = min(configuration.maxConcurrentDetails, videoIds.count)

                        func schedule(_ id: String) {
                            group.addTask {
                                try Task.checkCancellation()
                                try await delay(configuration)
                                do {
                                    return try await client.player(
                                        videoId: id, apiKey: apiKey, clientVersion: clientVersion
                                    )
                                } catch let error as YouTubeChannelError {
                                    // Rate limits are terminal; other per-video
                                    // failures are skipped so the batch continues.
                                    if error == .ipBlocked || error == .requestBlocked { throw error }
                                    return nil
                                }
                            }
                        }

                        while next < inFlightCap { schedule(videoIds[next]); next += 1 }
                        while let result = try await group.next() {
                            if let details = result { continuation.yield(details) }
                            if next < videoIds.count { schedule(videoIds[next]); next += 1 }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects ``detailsStream(for:configuration:)`` into an array.
    ///
    /// The result is sorted to match the order of `ids` (failed/skipped videos
    /// are simply absent). For very large channels prefer the streaming variant
    /// so you can persist as you go.
    ///
    /// - Throws: ``YouTubeChannelError`` only on terminal failures (rate limits);
    ///   individual unavailable videos are omitted, not thrown.
    public static func details(
        for ids: [String],
        configuration: Configuration = .default
    ) async throws -> [VideoDetails] {
        var byId: [String: VideoDetails] = [:]
        for try await details in detailsStream(for: ids, configuration: configuration) {
            byId[details.id] = details
        }
        // Restore input order; drop ids that produced no result.
        var seen = Set<String>()
        return ids.compactMap { input -> VideoDetails? in
            guard let id = try? VideoID.extract(from: input),
                  seen.insert(id).inserted else { return nil }
            return byId[id]
        }
    }

    // MARK: - Engine

    private static func run(
        input: String,
        tab: ContentTab,
        configuration: Configuration,
        emit: (ChannelVideo) -> Void
    ) async throws {
        let channelURL = try ChannelURL.url(from: input, tab: tab)
        let client = InnerTubeBrowseClient(config: configuration)
        let boot = try await client.bootstrap(url: channelURL, channel: input)

        // Emit the first grid page from the initial page load…
        var seen = Set<String>()
        for video in boot.firstPage.videos where seen.insert(video.id).inserted {
            emit(video)
        }

        // …then follow the continuation until the grid is exhausted.
        var token = boot.firstPage.nextToken
        while let current = token {
            try Task.checkCancellation()
            try await delay(configuration)
            let page = try await client.browse(
                token: current, apiKey: boot.apiKey, clientVersion: boot.clientVersion
            )
            // A page with items but no new IDs (or a repeated token) would loop
            // forever; stop when a page contributes nothing.
            var contributed = false
            for video in page.videos where seen.insert(video.id).inserted {
                emit(video)
                contributed = true
            }
            guard contributed, let next = page.nextToken, next != current else { break }
            token = next
        }
    }

    // MARK: - Helpers

    private static func delay(_ configuration: Configuration) async throws {
        guard configuration.pageDelay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(configuration.pageDelay * 1_000_000_000))
    }
}
