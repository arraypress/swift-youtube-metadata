# Swift YouTube Transcript

A Swift library for fetching YouTube video transcripts and metadata. No API key required, no browser needed — works entirely through YouTube's InnerTube API.

## Features

- 🎯 **Simple API** — fetch transcripts with a single async call
- 📝 **Full transcripts** with timestamps, durations, and language info
- 📊 **Video metadata** — title, author, views, duration, keywords, description, thumbnails
- 🌍 **Multi-language support** — request specific languages with automatic fallback
- 📋 **List available transcripts** — check what's available before fetching
- 🔒 **No API key required** — uses YouTube's public InnerTube API
- 🍎 **Cross-platform** — macOS, iOS, tvOS, watchOS
- ⚡ **Async/await** native — built for modern Swift concurrency
- 🛡️ **Typed error handling** — specific errors for every failure case

## Requirements

- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-youtube-transcript.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Choose version requirements

## Usage

### Fetch a Transcript

```swift
import YouTubeTranscript

// Using a video ID
let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")
print(result.plainText)

// Using a full URL (all formats supported)
let result = try await YouTubeTranscript.fetch("https://youtube.com/watch?v=dQw4w9WgXcQ")
let result = try await YouTubeTranscript.fetch("https://youtu.be/dQw4w9WgXcQ")
```

### Access Video Metadata

Metadata is extracted from the same API call — no additional requests.

```swift
let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")

if let video = result.video {
    print("Title: \(video.title)")
    print("Author: \(video.author)")
    print("Views: \(video.formattedViewCount)")
    print("Duration: \(video.formattedDuration)")
    print("Keywords: \(video.keywords.joined(separator: ", "))")
    print("Description: \(video.description)")
    print("Thumbnail: \(video.thumbnailUrl ?? "")")
    print("URL: \(video.url)")
}
```

### Timestamped Segments

```swift
let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")

// Quick dump of entire transcript with timestamps
print(result.timestampedText)

// Or iterate segments individually
for segment in result.segments {
    print("[\(segment.formattedStart)] \(segment.text)")
}
}
```

### Specify Language Preferences

Languages are tried in order. Manually created transcripts are preferred over auto-generated.

```swift
// Prefer German, fall back to English
let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ", languages: ["de", "en"])
print("Language: \(result.language)")
print("Auto-generated: \(result.isGenerated)")
```

### List Available Transcripts

Check what's available before fetching.

```swift
let list = try await YouTubeTranscript.list("dQw4w9WgXcQ")

for track in list.tracks {
    print("\(track.language) (\(track.languageCode)) — \(track.typeLabel)")
}

// Filter by type
print("Manual: \(list.manualTracks.count)")
print("Generated: \(list.generatedTracks.count)")
print("Languages: \(list.availableLanguages)")

// Find best match
if let track = list.findTrack(languages: ["en", "de"]) {
    print("Best match: \(track.language)")
}
```

### Error Handling

```swift
do {
    let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")
    print(result.plainText)
} catch YouTubeTranscriptError.transcriptsDisabled {
    print("No transcripts available for this video")
} catch YouTubeTranscriptError.noTranscriptFound(_, let requested, let available) {
    print("Requested \(requested) but only \(available) available")
} catch YouTubeTranscriptError.ipBlocked {
    print("Rate limited — try again later")
} catch YouTubeTranscriptError.videoUnavailable {
    print("Video doesn't exist or was removed")
} catch YouTubeTranscriptError.videoUnplayable(_, let reason) {
    print("Can't play: \(reason)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

## Models

### `FetchedTranscript`

The result of fetching a transcript.

| Property | Type | Description |
|----------|------|-------------|
| `videoId` | `String` | The YouTube video ID |
| `segments` | `[TranscriptSegment]` | Timestamped transcript segments |
| `video` | `VideoMetadata?` | Video metadata (title, author, etc.) |
| `language` | `String` | Language code of the fetched transcript |
| `isGenerated` | `Bool` | Whether the transcript is auto-generated |
| `typeLabel` | `String` | `"manual"` or `"auto"` |
| `plainText` | `String` | All segment text joined together |
| `timestampedText` | `String` | Full transcript with `[M:SS]` timestamps |
| `duration` | `Double` | Total transcript duration in seconds |
| `formattedDuration` | `String` | Duration as `"M:SS"` or `"H:MM:SS"` |
| `count` | `Int` | Number of segments |

### `TranscriptSegment`

A single timed segment.

| Property | Type | Description |
|----------|------|-------------|
| `text` | `String` | The text content |
| `start` | `Double` | Start time in seconds |
| `duration` | `Double` | Display duration in seconds |
| `end` | `Double` | End time in seconds (`start + duration`) |
| `language` | `String` | Language code |
| `formattedStart` | `String` | Start time as `"M:SS"` or `"H:MM:SS"` |

### `VideoMetadata`

Metadata about the video.

| Property | Type | Description |
|----------|------|-------------|
| `videoId` | `String` | YouTube video ID |
| `title` | `String` | Video title |
| `description` | `String` | Video description |
| `author` | `String` | Channel/author name |
| `channelId` | `String` | YouTube channel ID |
| `lengthSeconds` | `Int` | Duration in seconds |
| `formattedDuration` | `String` | Duration as `"M:SS"` or `"H:MM:SS"` |
| `viewCount` | `Int` | Total views |
| `formattedViewCount` | `String` | Views with grouping separators |
| `keywords` | `[String]` | Video tags/keywords |
| `thumbnailUrl` | `String?` | Best thumbnail URL |
| `url` | `String` | Full YouTube watch URL |
| `isLive` | `Bool` | Whether it's a livestream |

### `TranscriptTrack`

An available transcript track.

| Property | Type | Description |
|----------|------|-------------|
| `languageCode` | `String` | Language code (e.g., "en") |
| `language` | `String` | Human-readable name (e.g., "English") |
| `isGenerated` | `Bool` | Whether it's auto-generated |
| `typeLabel` | `String` | `"manual"` or `"auto"` |
| `isTranslatable` | `Bool` | Whether translation is available |

### `TranscriptList`

Result of listing available transcripts.

| Property | Type | Description |
|----------|------|-------------|
| `videoId` | `String` | The video ID |
| `tracks` | `[TranscriptTrack]` | All available tracks |
| `manualTracks` | `[TranscriptTrack]` | Manually created only |
| `generatedTracks` | `[TranscriptTrack]` | Auto-generated only |
| `availableLanguages` | `[String]` | All language codes |

## How It Works

This library uses YouTube's InnerTube API with the ANDROID client:

1. **Fetch the watch page** — establishes cookies and retrieves the `INNERTUBE_API_KEY`
2. **Call the InnerTube player API** — uses the ANDROID client context, which returns caption URLs that work without browser session tokens
3. **Fetch the transcript XML** — downloads and parses YouTube's timedtext format
4. **Extract metadata** — pulls video details from the same API response

The ANDROID client is critical — the WEB client returns caption URLs that require browser cookies and always return 0 bytes when fetched from native code.

## Limitations

- **Rate limiting** — YouTube may block IPs making too many requests. Reduce frequency or try a different network if you see `ipBlocked` errors.
- **No authentication** — Age-restricted and private videos require login, which is not supported.
- **Unofficial API** — YouTube may change their internal API at any time. Updates will be provided as needed.
- **PO tokens** — Some videos require a Proof of Origin token, indicated by the `poTokenRequired` error.

## Testing

```bash
swift test
```

The test suite includes unit tests for parsing, video ID extraction, and error handling, plus integration tests that hit YouTube's live API.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Credits

This library is inspired by and based on the approach used in [youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api) by [@jdepoix](https://github.com/jdepoix), the excellent Python library for YouTube transcript retrieval. The InnerTube API approach, consent cookie handling, and playability status checking are adapted from their work.

## License

MIT License — see LICENSE file for details.

## Author

Created by David Sherlock ([ArrayPress](https://github.com/arraypress)) in 2025.
