//
//  InnerTubeClient.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin client for YouTube's internal InnerTube API.
///
/// Handles the watch-page bootstrap (API key + client version + the initial
/// comment continuation token), EU consent cookies, the `youtubei/v1/next`
/// calls that page through comments, and rate-limit retries.
///
/// This is deliberately self-contained: the `YouTubeComments` target shares
/// no code with `YouTubeTranscript`.
struct InnerTubeClient {

    let config: YouTubeComments.Configuration
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init(config: YouTubeComments.Configuration) {
        self.config = config
        if let provided = config.session {
            self.session = provided
            self.cookieStorage = provided.configuration.httpCookieStorage ?? .shared
        } else {
            // Own cookie storage so the two package modules don't share
            // global consent/session state.
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

    /// The result of bootstrapping a video: everything needed to page comments.
    struct Bootstrap {
        let apiKey: String
        let clientVersion: String
        /// The initial ("Top") comment continuation token.
        let continuationToken: String
    }

    /// Fetches the watch page and extracts the InnerTube credentials plus the
    /// initial comment continuation token.
    func bootstrap(videoId: String) async throws(YouTubeCommentsError) -> Bootstrap {
        let html = try await fetchWatchPage(videoId: videoId)

        let apiKey = extractApiKey(from: html) ?? Self.fallbackApiKey
        let version = extractClientVersion(from: html) ?? Self.fallbackClientVersion

        // Parse ytInitialData for the comment section's continuation token.
        guard let initialData = extractInitialData(from: html) else {
            if html.contains("g-recaptcha") { throw .requestBlocked }
            throw .parsingError("Could not locate ytInitialData in watch page (\(videoId)).")
        }

        // The comment section renderer lives inside an itemSectionRenderer whose
        // continuationItemRenderer carries the first continuation token.
        let itemSection = JSONNav.first("itemSectionRenderer", in: initialData)
        let continuationRenderer = JSONNav.first("continuationItemRenderer", in: itemSection)
        guard let token = JSONNav.string("token", in: continuationRenderer) else {
            // No comment continuation → comments are off or unavailable.
            throw .commentsDisabled(videoId: videoId)
        }

        return Bootstrap(apiKey: apiKey, clientVersion: version, continuationToken: token)
    }

    // MARK: - next endpoint

    /// Calls `youtubei/v1/next` with a continuation token and returns the
    /// parsed JSON object.
    func next(token: String, apiKey: String, clientVersion: String) async throws(YouTubeCommentsError) -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/next?key=\(apiKey)&prettyPrint=false") else {
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
            throw .parsingError("Failed to encode next request body")
        }

        let data = try await performWithRetry(request)

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .parsingError("Invalid InnerTube JSON response")
        }
        return json
    }

    // MARK: - Watch page

    private func fetchWatchPage(videoId: String) async throws(YouTubeCommentsError) -> String {
        let html = try await rawWatchPage(videoId: videoId)

        // Handle YouTube's EU consent interstitial.
        if html.contains("consent.youtube.com") {
            try setConsentCookie(from: html, videoId: videoId)
            let retry = try await rawWatchPage(videoId: videoId)
            if retry.contains("consent.youtube.com") {
                throw .consentFailed(videoId: videoId)
            }
            return retry
        }
        return html
    }

    private func rawWatchPage(videoId: String) async throws(YouTubeCommentsError) -> String {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&hl=en") else {
            throw .invalidVideoId
        }
        var request = URLRequest(url: url)
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await performWithRetry(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw .parsingError("Failed to decode watch page HTML")
        }
        return html
    }

    private func setConsentCookie(from html: String, videoId: String) throws(YouTubeCommentsError) {
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

    // MARK: - Extraction

    private func extractApiKey(from html: String) -> String? {
        firstMatch(#""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#, in: html)
    }

    private func extractClientVersion(from html: String) -> String? {
        firstMatch(#""INNERTUBE_CONTEXT_CLIENT_VERSION":\s*"([\d.]+)""#, in: html)
            ?? firstMatch(#""clientVersion":\s*"([\d.]+)""#, in: html)
    }

    /// Extracts and parses the `ytInitialData` JSON object from the watch page.
    private func extractInitialData(from html: String) -> [String: Any]? {
        // `var ytInitialData = {...};` or `window["ytInitialData"] = {...};`
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

    private func performWithRetry(_ request: URLRequest) async throws(YouTubeCommentsError) -> Data {
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
                        throw YouTubeCommentsError.ipBlocked
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw YouTubeCommentsError.networkError("HTTP \(http.statusCode)")
                    }
                }
                return data
            } catch let error as YouTubeCommentsError {
                throw error
            } catch {
                // Transient URL errors: retry a bounded number of times.
                if attempt < config.maxRetries {
                    try? await backoff(attempt: attempt, response: nil)
                    attempt += 1
                    continue
                }
                throw YouTubeCommentsError.networkError(String(describing: error))
            }
        }
    }

    private func backoff(attempt: Int, response: HTTPURLResponse?) async throws(YouTubeCommentsError) {
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

    /// YouTube's public WEB InnerTube key. Stable for years; used only as a
    /// fallback if the watch-page scrape misses.
    static let fallbackApiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"

    /// Fallback WEB client version if the watch page doesn't expose one.
    static let fallbackClientVersion = "2.20240101.00.00"
}
