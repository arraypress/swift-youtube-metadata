//
//  InnerTubeBrowseClient.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin client for YouTube's internal InnerTube `browse` API.
///
/// Handles the channel-page bootstrap (API key + client version + the first
/// grid of uploads + the initial continuation token), EU consent cookies, the
/// `youtubei/v1/browse` calls that page through the remaining uploads, and
/// rate-limit retries.
///
/// This is deliberately self-contained: the `YouTubeChannel` target shares no
/// code with the other modules in the package.
struct InnerTubeBrowseClient {

    let config: YouTubeChannel.Configuration
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init(config: YouTubeChannel.Configuration) {
        self.config = config
        if let provided = config.session {
            self.session = provided
            self.cookieStorage = provided.configuration.httpCookieStorage ?? .shared
        } else {
            // Own cookie storage so the package modules don't share global
            // consent/session state.
            let storage = HTTPCookieStorage()
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.httpCookieAcceptPolicy = .always
            sessionConfig.httpShouldSetCookies = true
            sessionConfig.httpCookieStorage = storage
            sessionConfig.timeoutIntervalForRequest = config.requestTimeout
            sessionConfig.timeoutIntervalForResource = config.resourceTimeout
            self.session = URLSession(configuration: sessionConfig)
            self.cookieStorage = storage
        }
    }

    // MARK: - Bootstrap

    /// Everything a tab page yields in one fetch: the credentials, the channel
    /// metadata, the first page of items, and the token for the next page.
    struct Bootstrap {
        let apiKey: String
        let clientVersion: String
        let channelInfo: ChannelInfo?
        let firstPage: ChannelParser.Page
    }

    /// Fetches a channel tab page and extracts the InnerTube credentials, the
    /// channel metadata, the first grid of items, and the initial continuation
    /// token.
    func bootstrap(url: URL, channel: String) async throws(YouTubeChannelError) -> Bootstrap {
        let html = try await fetchPage(url: url, channel: channel)

        guard let apiKey = firstMatch(#""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#, in: html) else {
            if html.contains("g-recaptcha") { throw .requestBlocked }
            throw .parsingError("Could not extract the InnerTube API key from the channel page (\(channel)).")
        }
        let version = firstMatch(#""INNERTUBE_CONTEXT_CLIENT_VERSION":\s*"([\d.]+)""#, in: html)
            ?? firstMatch(#""clientVersion":\s*"([\d.]+)""#, in: html)
            ?? Self.fallbackClientVersion

        guard let initialData = extractInitialData(from: html) else {
            if html.contains("g-recaptcha") { throw .requestBlocked }
            throw .parsingError("Could not locate ytInitialData in channel page (\(channel)).")
        }

        let page = ChannelParser.parse(initialData)
        let channelInfo = ChannelParser.parseChannelInfo(initialData)

        // Distinguish "channel doesn't exist" from "valid channel, empty tab".
        // A real channel always renders `channelMetadataRenderer`; its absence on
        // an empty grid means the handle/ID resolved to nothing. A valid channel
        // with an empty tab (e.g. no Shorts or no live streams) yields no items
        // and no token — that is a legitimate empty result, not an error.
        if channelInfo == nil, page.videos.isEmpty, page.nextToken == nil {
            throw .channelUnavailable(channel: channel)
        }

        return Bootstrap(
            apiKey: apiKey,
            clientVersion: version,
            channelInfo: channelInfo,
            firstPage: page
        )
    }

    // MARK: - browse endpoint

    /// Calls `youtubei/v1/browse` with a continuation token and returns the
    /// parsed page.
    func browse(token: String, apiKey: String, clientVersion: String) async throws(YouTubeChannelError) -> ChannelParser.Page {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/browse?key=\(apiKey)&prettyPrint=false") else {
            throw .parsingError("Invalid InnerTube URL")
        }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "hl": "en",
                    "gl": "US",
                    "clientName": "WEB",
                    "clientVersion": clientVersion
                ]
            ],
            "continuation": token
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw .parsingError("Failed to encode browse request body")
        }

        let data = try await performWithRetry(request)

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .parsingError("Invalid InnerTube JSON response")
        }
        return ChannelParser.parse(json)
    }

    // MARK: - player endpoint

    /// Calls `youtubei/v1/player` (WEB client) for one video and parses its
    /// exact statistics.
    ///
    /// The WEB client is used because its response carries the `microformat`
    /// block with the precise publish date and category, which the ANDROID
    /// client omits. Metadata is present even when `playabilityStatus` is not
    /// `OK`, so playability is not gated here.
    func player(videoId: String, apiKey: String, clientVersion: String) async throws(YouTubeChannelError) -> VideoDetails {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)&prettyPrint=false") else {
            throw .parsingError("Invalid InnerTube URL")
        }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "hl": "en",
                    "gl": "US",
                    "clientName": "WEB",
                    "clientVersion": clientVersion
                ]
            ],
            "videoId": videoId
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw .parsingError("Failed to encode player request body")
        }

        let data = try await performWithRetry(request)

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .parsingError("Invalid InnerTube JSON response")
        }
        guard let details = VideoDetailsParser.parse(json, videoId: videoId) else {
            throw .channelUnavailable(channel: videoId)
        }
        return details
    }

    /// Reads the InnerTube API key and client version off a video's watch page,
    /// so the `player` endpoint can be called for that video.
    func watchPageCredentials(videoId: String) async throws(YouTubeChannelError) -> (apiKey: String, clientVersion: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&hl=en") else {
            throw .invalidChannel
        }
        let html = try await fetchPage(url: url, channel: videoId)
        guard let apiKey = firstMatch(#""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#, in: html) else {
            if html.contains("g-recaptcha") { throw .requestBlocked }
            throw .parsingError("Could not extract the InnerTube API key from the watch page (\(videoId)).")
        }
        let version = firstMatch(#""INNERTUBE_CONTEXT_CLIENT_VERSION":\s*"([\d.]+)""#, in: html)
            ?? firstMatch(#""clientVersion":\s*"([\d.]+)""#, in: html)
            ?? Self.fallbackClientVersion
        return (apiKey, version)
    }

    // MARK: - Channel page

    private func fetchPage(url: URL, channel: String) async throws(YouTubeChannelError) -> String {
        let html = try await rawPage(url: url)

        // Handle YouTube's EU consent interstitial.
        if html.contains("consent.youtube.com") {
            try setConsentCookie(from: html, channel: channel)
            let retry = try await rawPage(url: url)
            if retry.contains("consent.youtube.com") {
                throw .consentFailed(channel: channel)
            }
            return retry
        }
        return html
    }

    private func rawPage(url: URL) async throws(YouTubeChannelError) -> String {
        var request = URLRequest(url: url)
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await performWithRetry(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw .parsingError("Failed to decode channel page HTML")
        }
        return html
    }

    private func setConsentCookie(from html: String, channel: String) throws(YouTubeChannelError) {
        let value = firstMatch(#"name="v" value="(.*?)""#, in: html)
        let cookie = HTTPCookie(properties: [
            .domain: ".youtube.com",
            .path: "/",
            .name: "CONSENT",
            .value: "YES+" + (value ?? "cb.20210328-17-p0.en+FX"),
            .secure: "TRUE"
        ])
        if let cookie { cookieStorage.setCookie(cookie) }
    }

    /// Extracts and parses the `ytInitialData` JSON object from the channel page.
    private func extractInitialData(from html: String) -> [String: Any]? {
        for pattern in [
            #"ytInitialData"\s*\]\s*=\s*(\{.+?\})\s*;"#,
            #"ytInitialData\s*=\s*(\{.+?\})\s*;</script>"#,
            #"ytInitialData\s*=\s*(\{.+?\})\s*;"#
        ] {
            if let json = firstMatch(pattern, in: html, options: [.dotMatchesLineSeparators]),
               let data = json.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    // MARK: - Networking with retry

    private func performWithRetry(_ request: URLRequest) async throws(YouTubeChannelError) -> Data {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 || http.statusCode == 503 {
                        if attempt < config.maxRetries {
                            try await backoff(attempt: attempt, response: http)
                            attempt += 1
                            continue
                        }
                        throw YouTubeChannelError.ipBlocked
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw YouTubeChannelError.networkError("HTTP \(http.statusCode)")
                    }
                }
                return data
            } catch let error as YouTubeChannelError {
                throw error
            } catch {
                // Transient URL errors: retry a bounded number of times.
                if attempt < config.maxRetries {
                    try? await backoff(attempt: attempt, response: nil)
                    attempt += 1
                    continue
                }
                throw YouTubeChannelError.networkError(String(describing: error))
            }
        }
    }

    private func backoff(attempt: Int, response: HTTPURLResponse?) async throws(YouTubeChannelError) {
        // Honour Retry-After when present, else exponential backoff with jitter.
        var seconds = config.baseBackoff * pow(2.0, Double(attempt))
        if let retryAfter = response?.value(forHTTPHeaderField: "Retry-After"),
           let parsed = Double(retryAfter) {
            seconds = max(seconds, parsed)
        }
        seconds = min(seconds, config.maxBackoff)
        // Deterministic jitter (no Date/random dependency): vary by attempt.
        let jitter = 0.1 * Double((attempt % 3) + 1)
        let nanos = UInt64((seconds + jitter) * 1_000_000_000)
        do {
            try await Task.sleep(nanoseconds: nanos)
        } catch {
            throw .networkError("Cancelled during backoff")
        }
    }

    // MARK: - Regex helper

    private func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    // MARK: - Constants

    /// Browser-like user agent used for every request.
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// Fallback WEB client version if the channel page doesn't expose one.
    static let fallbackClientVersion = "2.20240101.00.00"
}
