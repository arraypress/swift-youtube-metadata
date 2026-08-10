//
//  YouTubeSearch.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//
//  Search YouTube — site-wide or within one channel — with no API key and no
//  quota. Uses the same InnerTube surface the website itself does: bootstrap the
//  credentials off a results page, then page through with continuation tokens.
//

import Foundation

/// Searches YouTube.
///
/// ```swift
/// // Site-wide
/// let hits = try await YouTubeSearch.videos("swift concurrency", limit: 20)
/// for hit in hits {
///     print("\(hit.title) — \(hit.author) (\(hit.viewCountText ?? "?"))")
/// }
///
/// // Ordered and filtered
/// let recent = try await YouTubeSearch.videos(
///     "wwdc",
///     filters: SearchFilters(sortBy: .uploadDate, uploadDate: .thisWeek, duration: .over20Minutes),
///     limit: 10
/// )
///
/// // Within one channel
/// let matches = try await YouTubeSearch.channel("@RickAstleyYT", query: "never", limit: 5)
/// ```
///
/// Results carry the rounded figures the website shows ("1.2M views", "3 years
/// ago"). For exact statistics on a given video, follow up with the
/// `YouTubeChannel` module's `details(for:)`.
public enum YouTubeSearch {

    // MARK: - Configuration

    /// Networking and politeness options.
    public struct Configuration: Sendable {

        /// A session to reuse. When `nil`, a private one is created with its own
        /// cookie storage so modules don't share consent state.
        public var session: URLSession?

        /// Per-request timeout in seconds.
        public var requestTimeout: TimeInterval

        /// Whole-resource timeout in seconds.
        public var resourceTimeout: TimeInterval

        /// How many times to retry a throttled or failed request.
        public var maxRetries: Int

        /// First backoff interval; doubles per attempt.
        public var baseBackoff: Double

        /// Ceiling for backoff.
        public var maxBackoff: Double

        /// Pause between continuation requests.
        ///
        /// Non-zero by default. Search paging is the easiest way to get an IP
        /// throttled, and a short pause costs far less than the backoff that
        /// follows a `429`.
        public var pageDelay: Double

        /// How many continuation pages to follow before stopping.
        ///
        /// Search has no natural end — YouTube will keep handing out tokens well
        /// past the point of usefulness — so paging is bounded by default.
        public var maxPages: Int

        /// Interface language passed to InnerTube.
        public var language: String

        /// Region passed to InnerTube.
        public var region: String

        public init(
            session: URLSession? = nil,
            requestTimeout: TimeInterval = 15,
            resourceTimeout: TimeInterval = 60,
            maxRetries: Int = 3,
            baseBackoff: Double = 1.0,
            maxBackoff: Double = 8.0,
            pageDelay: Double = 0.3,
            maxPages: Int = 20,
            language: String = "en",
            region: String = "US"
        ) {
            self.session = session
            self.requestTimeout = requestTimeout
            self.resourceTimeout = resourceTimeout
            self.maxRetries = maxRetries
            self.baseBackoff = baseBackoff
            self.maxBackoff = maxBackoff
            self.pageDelay = pageDelay
            self.maxPages = maxPages
            self.language = language
            self.region = region
        }

        public static var `default`: Configuration { Configuration() }
    }

    // MARK: - Site Search

    /// Searches YouTube and returns the matching videos.
    ///
    /// - Parameters:
    ///   - query: The search terms.
    ///   - filters: Ordering and filters. Defaults to relevance, unfiltered.
    ///   - limit: Optional cap on results. Strongly advised — search paging is
    ///     otherwise bounded only by ``Configuration/maxPages``.
    ///   - configuration: Networking/politeness options.
    /// - Returns: The matching videos, in result order.
    /// - Throws: ``YouTubeSearchError`` on failure.
    public static func videos(
        _ query: String,
        filters: SearchFilters = SearchFilters(),
        limit: Int? = nil,
        configuration: Configuration = .default
    ) async throws -> [SearchVideo] {
        var result: [SearchVideo] = []
        for try await video in stream(query, filters: filters, configuration: configuration) {
            result.append(video)
            if let limit, result.count >= limit { break }
        }
        return result
    }

    /// Streams search results as each page arrives.
    ///
    /// Breaking out of the loop cancels the underlying work, which is the
    /// cheapest way to stop early.
    ///
    /// ```swift
    /// for try await video in YouTubeSearch.stream("swift 6") {
    ///     if video.isLive { print("live: \(video.title)") }
    /// }
    /// ```
    public static func stream(
        _ query: String,
        filters: SearchFilters = SearchFilters(),
        configuration: Configuration = .default
    ) -> AsyncThrowingStream<SearchVideo, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try SearchURL.results(query: query, filters: filters)
                    try await run(
                        url: url,
                        endpoint: .search,
                        configuration: configuration
                    ) { video in
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

    // MARK: - Channel Search

    /// Searches within one channel's uploads.
    ///
    /// Far cheaper than enumerating a channel and filtering locally: YouTube
    /// does the matching server-side, so a large channel costs one page instead
    /// of dozens.
    ///
    /// - Parameters:
    ///   - channel: A channel ID (`UC…`), handle (`@name`), or channel URL.
    ///   - query: The search terms.
    ///   - limit: Optional cap on results.
    ///   - configuration: Networking/politeness options.
    /// - Returns: The matching videos from that channel.
    /// - Throws: ``YouTubeSearchError`` on failure.
    public static func channel(
        _ channel: String,
        query: String,
        limit: Int? = nil,
        configuration: Configuration = .default
    ) async throws -> [SearchVideo] {
        var result: [SearchVideo] = []
        for try await video in channelStream(channel, query: query, configuration: configuration) {
            result.append(video)
            if let limit, result.count >= limit { break }
        }
        return result
    }

    /// Streams a channel's matching uploads as each page arrives.
    public static func channelStream(
        _ channel: String,
        query: String,
        configuration: Configuration = .default
    ) -> AsyncThrowingStream<SearchVideo, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try SearchURL.channel(channel, query: query)
                    try await run(
                        url: url,
                        endpoint: .browse,
                        configuration: configuration
                    ) { video in
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

    // MARK: - Engine

    /// Bootstraps a results page and follows continuations until exhausted.
    private static func run(
        url: URL,
        endpoint: InnerTubeSearchClient.Endpoint,
        configuration: Configuration,
        emit: (SearchVideo) -> Void
    ) async throws {
        let client = InnerTubeSearchClient(config: configuration)
        let boot = try await client.bootstrap(url: url, subject: url.absoluteString)

        var seen = Set<String>()
        for video in boot.firstPage.videos where seen.insert(video.id).inserted {
            emit(video)
        }

        var token = boot.firstPage.nextToken
        var pages = 0

        while let current = token, pages < configuration.maxPages {
            if configuration.pageDelay > 0 {
                try await Task.sleep(nanoseconds: UInt64(configuration.pageDelay * 1_000_000_000))
            }

            let page = try await client.page(
                token: current,
                endpoint: endpoint,
                apiKey: boot.apiKey,
                clientVersion: boot.clientVersion
            )
            pages += 1

            var added = 0
            for video in page.videos where seen.insert(video.id).inserted {
                emit(video)
                added += 1
            }

            // Search continuations can keep handing out tokens after the results
            // dry up, and occasionally point back at a page already seen. A page
            // that contributes nothing new is the end of the road.
            if added == 0 { break }

            token = page.nextToken
        }
    }
}
