//
//  main.swift
//  YouTubeDump
//
//  Created by David Sherlock on 2025.
//
//  Example CLI composing YouTubeChannel + YouTubeTranscript + YouTubeComments
//  into a one-command channel dump. Dependency-free (hand-rolled arg parsing)
//  so the package keeps zero external dependencies.
//

import Foundation
import YouTubeChannel
import YouTubeTranscript
import YouTubeComments

// MARK: - Arguments

struct Options {
    var channel: String
    var limit: Int?
    var tab: ContentTab = .videos
    var wantTranscripts = false
    var transcriptFormat = "srt"        // srt | vtt | txt | json
    var languages = ["en"]
    var wantComments = false
    var commentLimit = 500
    var commentFormat = "tsv"           // tsv | csv | json
    var wantDetails = false
    var outDir: String?
}

func printUsage() {
    print("""
    yt-dump — dump a YouTube channel's videos, transcripts and comments.

    USAGE:
      yt-dump <channel> [options]

    <channel>  Channel ID (UC…), handle (@name), or channel URL.

    OPTIONS:
      --limit N               Max videos to process (default: all).
      --tab videos|shorts|streams   Which tab to enumerate (default: videos).
      --details               Fetch exact per-video stats (batched).
      --transcripts           Fetch transcripts.
      --transcript-format F   srt | vtt | txt | json (default: srt).
      --lang a,b,c            Transcript language preference (default: en).
      --comments              Fetch comments.
      --comment-limit N       Max comments per video (default: 500).
      --comment-format F      tsv | csv | json (default: tsv).
      --out DIR               Output directory (default: ./<handle>-dump).
      --help                  Show this help.

    EXAMPLE:
      yt-dump @GoogleDevelopers --limit 20 --details --transcripts --format srt
    """)
}

func parseArgs(_ argv: [String]) -> Options? {
    var positional: [String] = []
    var opts = Options(channel: "")
    var i = 0
    func next(_ flag: String) -> String? {
        i += 1
        guard i < argv.count else { fputs("Missing value for \(flag)\n", stderr); return nil }
        return argv[i]
    }
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--help", "-h": return nil
        case "--limit": guard let v = next(arg), let n = Int(v) else { return nil }; opts.limit = n
        case "--tab": guard let v = next(arg), let t = ContentTab(rawValue: v) else { fputs("Bad --tab\n", stderr); return nil }; opts.tab = t
        case "--details": opts.wantDetails = true
        case "--transcripts": opts.wantTranscripts = true
        case "--transcript-format", "--format": guard let v = next(arg) else { return nil }; opts.transcriptFormat = v
        case "--lang": guard let v = next(arg) else { return nil }; opts.languages = v.split(separator: ",").map(String.init)
        case "--comments": opts.wantComments = true
        case "--comment-limit": guard let v = next(arg), let n = Int(v) else { return nil }; opts.commentLimit = n
        case "--comment-format": guard let v = next(arg) else { return nil }; opts.commentFormat = v
        case "--out": guard let v = next(arg) else { return nil }; opts.outDir = v
        default:
            if arg.hasPrefix("--") { fputs("Unknown option: \(arg)\n", stderr); return nil }
            positional.append(arg)
        }
        i += 1
    }
    guard let channel = positional.first else { return nil }
    opts.channel = channel
    return opts
}

// MARK: - Helpers

func write(_ text: String, to path: String) throws {
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    try data.write(to: URL(fileURLWithPath: path))
}

/// A JSON-encodable view of a transcript (FetchedTranscript itself isn't Codable).
struct TranscriptJSON: Encodable {
    let videoId: String
    let language: String
    let isGenerated: Bool
    let segments: [TranscriptSegment]
}

func transcriptBody(_ t: FetchedTranscript, format: String) throws -> (text: String, ext: String) {
    switch format {
    case "srt": return (t.srt(), "srt")
    case "vtt": return (t.vtt(), "vtt")
    case "txt": return (t.plainText, "txt")
    case "json":
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let json = TranscriptJSON(videoId: t.videoId, language: t.language, isGenerated: t.isGenerated, segments: t.segments)
        return (String(data: try encoder.encode(json), encoding: .utf8) ?? "", "json")
    default:
        throw RuntimeError("Unknown transcript format '\(format)' (use srt|vtt|txt|json).")
    }
}

func commentsBody(_ comments: [Comment], format: String) throws -> (text: String, ext: String) {
    switch format {
    case "tsv": return (comments.tsv(), "comments.tsv")
    case "csv": return (comments.csv(), "comments.csv")
    case "json": return (String(data: try comments.jsonData(), encoding: .utf8) ?? "", "comments.json")
    default:
        throw RuntimeError("Unknown comment format '\(format)' (use tsv|csv|json).")
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    let description: String
    init(_ m: String) { description = m }
}

/// Filesystem-safe slug for the default output directory name.
func slug(_ s: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_@")
    let cleaned = String(s.map { allowed.contains($0) ? $0 : "-" })
    return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "channel" : cleaned
}

// MARK: - Run

func run(_ opts: Options) async throws {
    // 1. Channel info
    let info = try await YouTubeChannel.info(opts.channel)
    let outDir = opts.outDir ?? "./\(slug(info.handle ?? info.title))-dump"
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    print("Channel : \(info.title)  \(info.handle ?? "")")
    print("          \(info.subscriberText ?? "?") • \(info.videoCountText ?? "?")  (\(info.channelId))")
    print("Output  : \(outDir)\n")
    try writeJSON(info, to: "\(outDir)/channel.json")

    // 2. Video list
    print("Listing \(opts.tab.rawValue)…")
    let videos = try await YouTubeChannel.videos(opts.channel, tab: opts.tab, limit: opts.limit)
    print("  \(videos.count) items")
    try writeJSON(videos, to: "\(outDir)/videos.json")
    let ids = videos.map(\.id)

    // 3. Exact per-video stats (batched)
    if opts.wantDetails {
        print("Fetching exact stats for \(ids.count) videos…")
        let details = try await YouTubeChannel.details(for: ids)
        print("  \(details.count) ok, \(ids.count - details.count) skipped")
        try writeJSON(details, to: "\(outDir)/details.json")
    }

    // 4. Transcripts
    if opts.wantTranscripts {
        let dir = "\(outDir)/transcripts"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var ok = 0, skipped = 0
        for (n, id) in ids.enumerated() {
            do {
                let t = try await YouTubeTranscript.fetch(id, languages: opts.languages)
                let body = try transcriptBody(t, format: opts.transcriptFormat)
                try write(body.text, to: "\(dir)/\(id).\(body.ext)")
                ok += 1
            } catch {
                skipped += 1
            }
            if (n + 1) % 10 == 0 || n + 1 == ids.count {
                print("  transcripts \(n + 1)/\(ids.count)  (\(ok) ok, \(skipped) none)")
            }
        }
    }

    // 5. Comments
    if opts.wantComments {
        let dir = "\(outDir)/comments"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var ok = 0, skipped = 0
        for (n, id) in ids.enumerated() {
            do {
                let comments = try await YouTubeComments.fetch(id, limit: opts.commentLimit)
                let body = try commentsBody(comments, format: opts.commentFormat)
                try write(body.text, to: "\(dir)/\(id).\(body.ext)")
                ok += 1
            } catch {
                skipped += 1
            }
            if (n + 1) % 10 == 0 || n + 1 == ids.count {
                print("  comments \(n + 1)/\(ids.count)  (\(ok) ok, \(skipped) none)")
            }
        }
    }

    print("\n✅ Done → \(outDir)")
}

// MARK: - Entry

let argv = Array(CommandLine.arguments.dropFirst())
guard let opts = parseArgs(argv) else {
    printUsage()
    exit(argv.isEmpty ? 0 : 1)
}

do {
    try await run(opts)
} catch {
    fputs("❌ \(error)\n", stderr)
    exit(1)
}
