# Swift YouTube Metadata

A dependency-free Swift library for fetching YouTube video transcripts and metadata. It uses YouTube's InnerTube API with the ANDROID client to reliably retrieve captions and video details with no API key, browser, or authentication — returning transcript segments and rich video metadata from a single call.

## Features

- 📝 **Transcript fetching** — `fetch(_:)` returns a `FetchedTranscript` with timed segments, plain text, and timestamped text
- 🎬 **Video metadata included** — the same call also returns `VideoMetadata` (title, author, description, view count, duration, keywords, thumbnail) at no extra request
- 🌐 **Language preferences** — pass an ordered list of language codes; manual transcripts are preferred over auto-generated, with prefix matching (`"en"` matches `"en-US"`)
- 📋 **Track discovery** — `list(_:)` returns a `TranscriptList` of available tracks without downloading any transcript content
- 🔗 **Flexible input** — accepts raw 11-character video IDs and watch, short (`youtu.be`), embed, Shorts, live, and `/v/` URLs
- 🤖 **No API key** — talks directly to YouTube's InnerTube API using the ANDROID client, whose caption URLs work without browser session tokens
- 🍪 **Consent handling** — automatically detects and clears YouTube's EU cookie-consent interstitial
- ⏱️ **Formatting helpers** — segments and metadata expose `formattedStart`, `formattedDuration`, and `formattedViewCount`
- 🛡️ **Typed errors** — `YouTubeTranscriptError` distinguishes IP blocks, disabled transcripts, unavailable videos, PO-token requirements, and more, each carrying the relevant video ID
- 📦 **Sendable & Codable models** — transcript and metadata types are `Sendable`, and the segment, track, and metadata models are `Codable`

> **Note:** The module is named `YouTubeTranscript` — import it with `import YouTubeTranscript`.

## Requirements

- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-youtube-metadata.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies…** and enter `https://github.com/arraypress/swift-youtube-metadata`.

## Usage

### Fetching a transcript

```swift
import YouTubeTranscript

// Supports video IDs and full URLs
let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")

print(result.plainText)
print(result.video?.title ?? "")
print("Segments: \(result.count)")
print("Type: \(result.typeLabel)")           // "manual" or "auto"
print("Duration: \(result.formattedDuration)")
```

### Language preferences

```swift
import YouTubeTranscript

// Prefer German, then English
let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ", languages: ["de", "en"])
print(result.language)
```

### Timed segments

```swift
import YouTubeTranscript

let result = try await YouTubeTranscript.fetch("https://youtu.be/dQw4w9WgXcQ")

for segment in result.segments {
    print("[\(segment.formattedStart)] \(segment.text)")
}

// Or all at once
print(result.timestampedText)
```

### Listing available transcripts

```swift
import YouTubeTranscript

let list = try await YouTubeTranscript.list("dQw4w9WgXcQ")

print("Manual: \(list.manualTracks.count)")
print("Auto: \(list.generatedTracks.count)")
print("Languages: \(list.availableLanguages)")

if let best = list.findTrack(languages: ["en", "de"]) {
    print("Best match: \(best.language) (\(best.typeLabel))")
}
```

### Video metadata

```swift
import YouTubeTranscript

let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")

if let video = result.video {
    print("\(video.title) by \(video.author)")
    print("\(video.formattedViewCount) views · \(video.formattedDuration)")
    print(video.url)
}
```

### Error handling

```swift
import YouTubeTranscript

do {
    let result = try await YouTubeTranscript.fetch(videoId)
} catch YouTubeTranscriptError.transcriptsDisabled {
    print("No captions on this video")
} catch YouTubeTranscriptError.ipBlocked {
    print("Rate limited — try again later")
} catch {
    print(error.localizedDescription)
}
```

## How It Works

1. Fetches the YouTube watch page to establish cookies and extract the InnerTube API key (handling the EU consent page if shown).
2. Calls the InnerTube player API (`youtubei/v1/player`) with the ANDROID client context.
3. Extracts caption track URLs and `videoDetails` metadata from the response, then validates the video's playability status.
4. Fetches and parses the transcript XML for the best matching track.

The ANDROID client is used because its caption URLs work without browser session tokens, unlike the WEB client whose URLs require a browser session.

## Models

| Type | Kind | Description |
|------|------|-------------|
| `FetchedTranscript` | struct | `videoId`, `segments`, `video`, `language`, `isGenerated`, plus `plainText`, `timestampedText`, `duration`, `count`, `typeLabel`, `formattedDuration` |
| `TranscriptSegment` | struct (Codable) | `text`, `start`, `duration`, `language`, plus `end` and `formattedStart` |
| `TranscriptList` | struct | `videoId`, `tracks`, plus `manualTracks`, `generatedTracks`, `availableLanguages`, and `findTrack(languages:)` |
| `TranscriptTrack` | struct (Codable) | `languageCode`, `language`, `isGenerated`, `isTranslatable`, `typeLabel` |
| `VideoMetadata` | struct (Codable) | `videoId`, `title`, `description`, `author`, `channelId`, `lengthSeconds`, `viewCount`, `keywords`, `thumbnailUrl`, `isLive`, plus `url`, `formattedDuration`, `formattedViewCount` |
| `YouTubeTranscriptError` | enum | Typed errors with `errorDescription` |

## Use Cases

- Generating searchable text from video content
- Summarising or analysing video transcripts with an LLM
- Building captions/subtitle tooling
- Enriching a video library with titles, durations, and view counts

## Testing

```bash
swift test
```

The test suite exercises video-ID extraction, transcript fetching and parsing, track listing, metadata extraction, and error handling.

## Credits

Inspired by [youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api) by [@jdepoix](https://github.com/jdepoix).

## License

MIT License — see LICENSE file for details.

## Author

Created by David Sherlock ([ArrayPress](https://github.com/arraypress)) in 2026.
