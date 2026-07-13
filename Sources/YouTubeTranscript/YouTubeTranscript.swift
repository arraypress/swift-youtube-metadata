//
//  YouTubeTranscript.swift
//  YouTubeTranscript
//
//  Created by David Sherlock on 2025.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetch transcripts and metadata from YouTube videos.
///
/// Uses YouTube's InnerTube API with the ANDROID client to reliably retrieve
/// transcripts without requiring an API key, browser, or authentication.
///
/// ## Quick Start
///
/// ```swift
/// import YouTubeTranscript
///
/// // Fetch transcript (supports URLs and video IDs)
/// let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")
/// print(result.plainText)
/// print(result.video?.title ?? "")
///
/// // Specify preferred languages
/// let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ", languages: ["de", "en"])
///
/// // List available transcripts without fetching content
/// let list = try await YouTubeTranscript.list("dQw4w9WgXcQ")
/// for track in list.tracks {
///     print("\(track.language) — \(track.isGenerated ? "auto" : "manual")")
/// }
/// ```
///
/// ## How It Works
///
/// 1. Fetches the YouTube watch page to establish cookies and extract the InnerTube API key
/// 2. Calls the InnerTube player API with the ANDROID client context
/// 3. Extracts caption track URLs and video metadata from the response
/// 4. Fetches and parses the transcript XML
///
/// The ANDROID client is used because its caption URLs work without browser
/// session tokens, unlike the WEB client which requires cookies.
///
/// ## Credits
///
/// Inspired by [youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api)
/// by [@jdepoix](https://github.com/jdepoix).
public enum YouTubeTranscript {

    // MARK: - Configuration

    /// Browser-like user agent for the initial page fetch.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// Shared session with cookie persistence for consent handling.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        // Explicit timeouts so a hung connection can't block the await forever.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Fetches the transcript for a YouTube video.
    ///
    /// Supports both video IDs and full YouTube URLs. Automatically selects
    /// the best available transcript based on language preferences, preferring
    /// manually created transcripts over auto-generated ones.
    ///
    /// ```swift
    /// // Simple fetch
    /// let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")
    ///
    /// // With language preference
    /// let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ", languages: ["de", "en"])
    ///
    /// // Access everything
    /// print(result.video?.title ?? "")
    /// print(result.video?.description ?? "")
    /// print(result.plainText)
    /// print(result.segments.count)
    /// ```
    ///
    /// - Parameters:
    ///   - input: A YouTube video ID (e.g., `"dQw4w9WgXcQ"`) or full URL.
    ///   - languages: Language codes in descending priority. Defaults to `["en"]`.
    /// - Throws: ``YouTubeTranscriptError`` if the transcript cannot be retrieved.
    /// - Returns: A ``FetchedTranscript`` containing segments and video metadata.
    public static func fetch(_ input: String, languages: [String] = ["en"]) async throws -> FetchedTranscript {
        let videoId = try VideoID.extract(from: input)

        // Fetch the watch page (establishes cookies, provides API key)
        let html = try await fetchVideoPage(videoId: videoId)

        // Extract the InnerTube API key
        let apiKey = try extractApiKey(from: html, videoId: videoId)

        // Call InnerTube player API (ANDROID client)
        let playerData = try await fetchPlayerData(videoId: videoId, apiKey: apiKey)

        // Extract metadata from videoDetails
        let metadata = extractMetadata(from: playerData, videoId: videoId)

        // Extract caption tracks
        let tracks = try extractTracks(from: playerData, videoId: videoId)

        // Find the best matching track
        let list = TranscriptList(videoId: videoId, tracks: tracks)
        guard let track = list.findTrack(languages: languages) else {
            throw YouTubeTranscriptError.noTranscriptFound(
                videoId: videoId,
                requestedLanguages: languages,
                availableLanguages: list.availableLanguages
            )
        }

        // Fetch and parse transcript content
        let segments = try await fetchTranscriptContent(track: track, videoId: videoId)

        return FetchedTranscript(
            videoId: videoId,
            segments: segments,
            video: metadata,
            language: track.languageCode,
            isGenerated: track.isGenerated
        )
    }

    /// Lists available transcripts for a YouTube video without fetching content.
    ///
    /// Use this to discover which languages are available before deciding
    /// which transcript to fetch.
    ///
    /// ```swift
    /// let list = try await YouTubeTranscript.list("dQw4w9WgXcQ")
    ///
    /// print("Manual: \(list.manualTracks.count)")
    /// print("Auto: \(list.generatedTracks.count)")
    /// print("Languages: \(list.availableLanguages)")
    ///
    /// if let best = list.findTrack(languages: ["en", "de"]) {
    ///     print("Best match: \(best.language)")
    /// }
    /// ```
    ///
    /// - Parameter input: A YouTube video ID or full URL.
    /// - Throws: ``YouTubeTranscriptError`` if the video or transcript data cannot be accessed.
    /// - Returns: A ``TranscriptList`` containing available tracks.
    public static func list(_ input: String) async throws -> TranscriptList {
        let videoId = try VideoID.extract(from: input)
        let html = try await fetchVideoPage(videoId: videoId)
        let apiKey = try extractApiKey(from: html, videoId: videoId)
        let playerData = try await fetchPlayerData(videoId: videoId, apiKey: apiKey)
        let tracks = try extractTracks(from: playerData, videoId: videoId)

        return TranscriptList(videoId: videoId, tracks: tracks)
    }

    // MARK: - Page Fetching

    /// Fetches the YouTube watch page, handling consent cookies if needed.
    private static func fetchVideoPage(videoId: String) async throws -> String {
        let html = try await fetchHtml(videoId: videoId)

        // Handle YouTube's EU consent page
        if html.contains("action=\"https://consent.youtube.com/s\"") {
            try setConsentCookie(from: html, videoId: videoId)
            let retryHtml = try await fetchHtml(videoId: videoId)
            if retryHtml.contains("action=\"https://consent.youtube.com/s\"") {
                throw YouTubeTranscriptError.consentFailed(videoId: videoId)
            }
            return retryHtml
        }

        return html
    }

    /// Performs a raw HTML fetch for a YouTube watch page.
    private static func fetchHtml(videoId: String) async throws -> String {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
            throw YouTubeTranscriptError.invalidVideoId
        }

        var request = URLRequest(url: url)
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await perform(request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            throw YouTubeTranscriptError.ipBlocked
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode watch page HTML")
        }

        return html
    }

    /// Performs a request, converting transport failures (timeouts, DNS, offline)
    /// into a typed ``YouTubeTranscriptError/networkError(_:)`` instead of letting
    /// a raw `URLError` escape the library's typed-error contract.
    private static func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as YouTubeTranscriptError {
            throw error
        } catch {
            throw YouTubeTranscriptError.networkError(String(describing: error))
        }
    }

    // MARK: - Consent Handling

    /// Creates a consent cookie from YouTube's EU consent form.
    private static func setConsentCookie(from html: String, videoId: String) throws {
        guard let regex = try? NSRegularExpression(pattern: "name=\"v\" value=\"(.*?)\""),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let valueRange = Range(match.range(at: 1), in: html) else {
            throw YouTubeTranscriptError.consentFailed(videoId: videoId)
        }

        if let cookie = HTTPCookie(properties: [
            .domain: ".youtube.com",
            .path: "/",
            .name: "CONSENT",
            .value: "YES+" + String(html[valueRange]),
            .secure: "TRUE"
        ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    // MARK: - InnerTube API

    /// Extracts the InnerTube API key from the watch page HTML.
    private static func extractApiKey(from html: String, videoId: String) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: "\"INNERTUBE_API_KEY\":\\s*\"([a-zA-Z0-9_-]+)\""),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let keyRange = Range(match.range(at: 1), in: html) else {

            if html.contains("class=\"g-recaptcha\"") {
                throw YouTubeTranscriptError.ipBlocked
            }
            throw YouTubeTranscriptError.parsingError("Could not find INNERTUBE_API_KEY in watch page")
        }

        return String(html[keyRange])
    }

    /// Calls the InnerTube player API with the ANDROID client context.
    private static func fetchPlayerData(videoId: String, apiKey: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)") else {
            throw YouTubeTranscriptError.parsingError("Invalid InnerTube URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")

        // Build request body with ANDROID client context.
        // The ANDROID client returns caption URLs that work without browser
        // cookies or session tokens — the WEB client's URLs require a browser
        // session and return 0 bytes when fetched from native code.
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "20.10.38"
                ]
            ],
            "videoId": videoId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await perform(request)

        if (response as? HTTPURLResponse)?.statusCode == 429 {
            throw YouTubeTranscriptError.ipBlocked
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeTranscriptError.parsingError("Invalid InnerTube JSON response")
        }

        try checkPlayability(json, videoId: videoId)

        return json
    }

    /// Validates the playability status from the InnerTube response.
    ///
    /// Mirrors the Python library's `_assert_playability` check.
    private static func checkPlayability(_ json: [String: Any], videoId: String) throws {
        guard let playability = json["playabilityStatus"] as? [String: Any] else { return }

        let status = playability["status"] as? String ?? ""
        let reason = playability["reason"] as? String ?? ""

        switch status {
        case "LOGIN_REQUIRED":
            if reason.contains("bot") || reason.contains("Sign in") {
                throw YouTubeTranscriptError.requestBlocked
            }
            if reason.contains("inappropriate") {
                throw YouTubeTranscriptError.videoUnplayable(videoId: videoId, reason: "Age-restricted content")
            }
        case "ERROR":
            if reason.contains("unavailable") {
                throw YouTubeTranscriptError.videoUnavailable(videoId: videoId)
            }
            throw YouTubeTranscriptError.videoUnplayable(videoId: videoId, reason: reason)
        case "UNPLAYABLE":
            throw YouTubeTranscriptError.videoUnplayable(videoId: videoId, reason: reason)
        default:
            break
        }
    }

    // MARK: - Track Extraction

    /// Extracts caption tracks from the InnerTube player response.
    private static func extractTracks(from playerData: [String: Any], videoId: String) throws -> [TranscriptTrack] {
        guard let captions = playerData["captions"] as? [String: Any],
              let renderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let rawTracks = renderer["captionTracks"] as? [[String: Any]],
              !rawTracks.isEmpty else {
            throw YouTubeTranscriptError.transcriptsDisabled(videoId: videoId)
        }

        return rawTracks.compactMap { raw -> TranscriptTrack? in
            guard let baseUrl = raw["baseUrl"] as? String,
                  let languageCode = raw["languageCode"] as? String else { return nil }

            // Extract language name from nested structure
            let languageName: String
            if let name = raw["name"] as? [String: Any],
               let runs = name["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String {
                languageName = text
            } else if let simpleText = (raw["name"] as? [String: Any])?["simpleText"] as? String {
                languageName = simpleText
            } else {
                languageName = languageCode
            }

            return TranscriptTrack(
                languageCode: languageCode,
                language: languageName,
                isGenerated: (raw["kind"] as? String) == "asr",
                isTranslatable: raw["isTranslatable"] as? Bool ?? false,
                baseUrl: baseUrl
            )
        }
    }

    // MARK: - Transcript Content

    /// Fetches and parses the transcript XML for a specific track.
    private static func fetchTranscriptContent(track: TranscriptTrack, videoId: String) async throws -> [TranscriptSegment] {
        var baseUrl = track.baseUrl
        baseUrl = baseUrl.replacingOccurrences(of: "&fmt=srv3", with: "")

        if baseUrl.contains("&exp=xpe") {
            throw YouTubeTranscriptError.poTokenRequired(videoId: videoId)
        }

        guard let url = URL(string: baseUrl) else {
            throw YouTubeTranscriptError.parsingError("Invalid transcript URL")
        }

        var request = URLRequest(url: url)
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await perform(request)

        // The timedtext endpoint is rate-limited too; without this check a 429
        // here would surface as a misleading `emptyTranscript`.
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                throw YouTubeTranscriptError.ipBlocked
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw YouTubeTranscriptError.networkError("HTTP \(httpResponse.statusCode) fetching transcript")
            }
        }

        guard let xmlString = String(data: data, encoding: .utf8), !xmlString.isEmpty else {
            throw YouTubeTranscriptError.emptyTranscript(videoId: videoId)
        }

        let segments = TranscriptParser.parse(xmlString, language: track.languageCode)

        if segments.isEmpty {
            throw YouTubeTranscriptError.emptyTranscript(videoId: videoId)
        }

        return segments
    }

    // MARK: - Metadata Extraction

    /// Extracts video metadata from the InnerTube player response.
    private static func extractMetadata(from playerData: [String: Any], videoId: String) -> VideoMetadata? {
        guard let details = playerData["videoDetails"] as? [String: Any] else { return nil }

        let thumbnails = (details["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let bestThumbnail = thumbnails?.last?["url"] as? String

        return VideoMetadata(
            videoId: details["videoId"] as? String ?? videoId,
            title: details["title"] as? String ?? "",
            description: details["shortDescription"] as? String ?? "",
            author: details["author"] as? String ?? "",
            channelId: details["channelId"] as? String ?? "",
            lengthSeconds: Int(details["lengthSeconds"] as? String ?? "0") ?? 0,
            viewCount: Int(details["viewCount"] as? String ?? "0") ?? 0,
            keywords: details["keywords"] as? [String] ?? [],
            thumbnailUrl: bestThumbnail,
            isLive: details["isLiveContent"] as? Bool ?? false
        )
    }
}
