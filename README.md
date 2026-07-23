# Swift YouTube Metadata

A dependency-free Swift package for fetching YouTube data via YouTube's internal InnerTube API — no API key, browser, or authentication. It provides three independent libraries:

- **`YouTubeTranscript`** — video transcripts and rich metadata from a single call, with SRT/VTT export.
- **`YouTubeComments`** — public comment downloads (with replies, hearts, pins, membership badges, and paid chips), exportable to CSV/TSV/JSON. See [Downloading comments](#downloading-comments-youtubecomments).
- **`YouTubeChannel`** — enumerate an entire channel's uploads, Shorts, and live streams, with channel info and exact per-video stats. See [Enumerating a channel](#enumerating-a-channel-youtubechannel).

## Features

- 📝 **Transcript fetching** — `fetch(_:)` returns a `FetchedTranscript` with timed segments, plain text, timestamped text, and `srt()` / `vtt()` subtitle export
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

### Exporting subtitles (SRT / VTT)

```swift
import YouTubeTranscript

let result = try await YouTubeTranscript.fetch("dQw4w9WgXcQ")

let srt = result.srt()   // SubRip, with overlapping auto-caption cues clamped
let vtt = result.vtt()   // WebVTT
try srt.write(to: url, atomically: true, encoding: .utf8)
```

### Speaker turns

Interview and podcast captions often include `>>` speaker-change markers.
`result.turns` groups the segments into ``TranscriptTurn``s at those markers —
useful for reading a two-party conversation or feeding an LLM per-turn instead
of one blob.

```swift
let result = try await YouTubeTranscript.fetch(videoId)

for turn in result.turns {
    print("[\(turn.formattedStart)] Speaker \(turn.speaker + 1): \(turn.text)")
}
```

> **Note:** YouTube captions carry no speaker *names*, only change markers, and
> auto-generated tracks mark changes imperfectly. So `turn.speaker` is a
> best-effort alternating index (0, 1, 0, …) — reliable as a *turn* boundary,
> approximate as *speaker identity*. True diarization needs the audio and an ML
> model.

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

## Downloading comments (`YouTubeComments`)

This package ships a second, independent library — `YouTubeComments` — for downloading a video's public comments. It's a self-contained target (it shares no code with `YouTubeTranscript`) and uses the InnerTube `youtubei/v1/next` endpoint with continuation-token pagination, again with **no API key, quota, or authentication**.

It captures fields the official YouTube Data API does **not** expose: creator hearts, pinned status, membership badges, and paid "Super Thanks" chips.

```swift
import YouTubeComments

// Fetch everything (top-level comments + replies), thread order preserved:
let comments = try await YouTubeComments.fetch("dQw4w9WgXcQ")

// First 200 newest, no replies:
let recent = try await YouTubeComments.fetch(
    "https://youtu.be/dQw4w9WgXcQ",
    sortBy: .newest,
    includeReplies: false,
    limit: 200
)

// Stream page-by-page for very large threads:
for try await comment in YouTubeComments.stream("dQw4w9WgXcQ") {
    if comment.isHearted { print("❤️ \(comment.author): \(comment.text)") }
}
```

### Exporting

```swift
let tsv  = comments.tsv()            // publishedTimeText, simpleText, votes, author,
                                     // isReply, isHearted, isPinned, isPaid, paidAmount,
                                     // isSponsor, sponsorshipMonths
let csv  = comments.csv()            // RFC-4180 quoted
let json = try comments.jsonData()   // Codable Comment array
```

### Comment model

| Field | Description |
|-------|-------------|
| `id`, `text`, `author`, `authorChannelId`, `authorAvatarUrl` | Identity + content |
| `publishedTimeText`, `isEdited` | e.g. `"1 month ago (edited)"` |
| `likeCountText`, `likeCount` | As displayed (`"85K"`) + best-effort Int |
| `replyCount`, `isReply`, `parentId` | Threading |
| `isHearted`, `isPinned`, `pinnedByText` | Creator signals |
| `isVerified`, `isChannelOwner` | Author flags |
| `isPaid`, `paidAmount` | Super Thanks |
| `isSponsor`, `sponsorshipMonths`, `sponsorBadgeText` | Membership |

Networking, retries/backoff, timeouts, and a politeness delay are configurable via `YouTubeComments.Configuration`.

> **Note:** These are undocumented endpoints and this is against YouTube's Terms of Service. Fetch responsibly; expect `YouTubeCommentsError.ipBlocked` if you go too fast.

## Enumerating a channel (`YouTubeChannel`)

The third independent library — `YouTubeChannel` — walks a channel's tabs to return **every** upload (not just the ~15 the public RSS feed exposes), using the InnerTube `browse` endpoint with continuation-token pagination. Like the others, it's self-contained and needs **no API key, quota, or authentication**.

```swift
import YouTubeChannel

// Every video ID on a channel (accepts channel IDs, @handles, and URLs)
let ids = try await YouTubeChannel.videoIDs("@GoogleDevelopers")

// Items with grid metadata (title, length, views, published, thumbnail, isLive)
let videos = try await YouTubeChannel.videos("@GoogleDevelopers", limit: 200)

// Other tabs
let shorts  = try await YouTubeChannel.videos("@MrBeast", tab: .shorts)
let streams = try await YouTubeChannel.videos("@LofiGirl", tab: .streams)

// Channel-level info (subscribers, description, avatar) — one page load
let info = try await YouTubeChannel.info("@MrBeast")

// Stream page-by-page for very large channels
for try await video in YouTubeChannel.stream("@GoogleDevelopers") {
    print(video.id, video.title)
}
```

### Exact per-video stats

The grid only carries rounded text (`"4.7K views"`). For precise numbers — exact view count, length in seconds, publish date, description, category, keywords — fetch details (one request per video, reusing credentials and capping concurrency):

```swift
let ids = try await YouTubeChannel.videoIDs("@GoogleDevelopers")
for try await details in YouTubeChannel.detailsStream(for: ids) {
    print(details.id, details.viewCount ?? -1, details.publishDate ?? "")
}
```

Networking, retries/backoff, politeness delay, and concurrency are configurable via `YouTubeChannel.Configuration`.

### Example CLI

The package includes a `YouTubeDump` executable that composes all three libraries into a one-command channel dump:

```bash
swift run YouTubeDump @GoogleDevelopers --limit 20 --details --transcripts --format srt --comments
```

## Use Cases

- Generating searchable text from video content
- Archiving an entire channel's videos, transcripts, and comments
- Summarising or analysing video transcripts with an LLM
- Building captions/subtitle tooling
- Enriching a video library with titles, durations, and view counts
- Exporting comment datasets for sentiment analysis, social listening, or research

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
