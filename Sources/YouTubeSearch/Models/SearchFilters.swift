//
//  SearchFilters.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//
//  YouTube encodes search filters into the `sp` query parameter as a
//  base64-encoded protocol buffer. Encoding it properly — rather than shipping a
//  table of copied magic strings — is what makes filter *combinations* work:
//  "long videos from this week, sorted by view count" has no published constant.
//

import Foundation

/// Filters and ordering for a search.
public struct SearchFilters: Sendable, Equatable {

    // MARK: Ordering

    /// How results are ordered.
    public enum SortBy: Int, Sendable, CaseIterable, Codable {
        case relevance = 0
        case rating = 1
        case uploadDate = 2
        case viewCount = 3
    }

    // MARK: Filters

    /// How recently the video was published.
    public enum UploadDate: Int, Sendable, CaseIterable, Codable {
        case lastHour = 1
        case today = 2
        case thisWeek = 3
        case thisMonth = 4
        case thisYear = 5
    }

    /// What kind of result to return.
    ///
    /// - Warning: Only ``video`` is parsed today. The other cases filter
    ///   correctly server-side, but ``SearchParser`` reads `videoRenderer` and
    ///   nothing else, so a channel or playlist search filters to results this
    ///   library then discards — an empty array rather than an error. They are
    ///   kept here because the wire values are part of the format, but do not
    ///   use them until there are models to receive them.
    public enum ResultType: Int, Sendable, CaseIterable, Codable {
        case video = 1
        case channel = 2
        case playlist = 3
        case movie = 4
    }

    /// How long the video is.
    ///
    /// Named for the band rather than the boundary: YouTube has moved the short
    /// cut-off between four and three minutes over the years, and the labels in
    /// its own UI change with it. The wire values are stable; the minute counts
    /// are not, so they stay in the documentation where they can be wrong
    /// harmlessly.
    public enum Duration: Int, Sendable, CaseIterable, Codable {

        /// Short videos — currently labelled "Under 3 minutes".
        case short = 1

        /// Long videos — currently labelled "Over 20 minutes".
        case long = 2

        /// Mid-length videos — currently labelled "3–20 minutes".
        case medium = 3
    }

    // MARK: Properties

    public var sortBy: SortBy
    public var uploadDate: UploadDate?
    public var type: ResultType?
    public var duration: Duration?

    // MARK: Initialisation

    public init(
        sortBy: SortBy = .relevance,
        uploadDate: UploadDate? = nil,
        type: ResultType? = nil,
        duration: Duration? = nil
    ) {
        self.sortBy = sortBy
        self.uploadDate = uploadDate
        self.type = type
        self.duration = duration
    }

    /// Whether these filters are all defaults, in which case no `sp` is sent.
    public var isDefault: Bool {
        sortBy == .relevance && uploadDate == nil && type == nil && duration == nil
    }

    // MARK: Encoding

    /// The `sp` query parameter value, or `nil` when nothing is filtered.
    ///
    /// Layout, as YouTube defines it:
    ///
    /// ```
    /// field 1 (varint)  sort order
    /// field 2 (message) filters
    ///     field 1 (varint)  upload date
    ///     field 2 (varint)  result type
    ///     field 3 (varint)  duration
    /// ```
    var parameter: String? {
        var filters = Data()
        if let uploadDate {
            filters.append(0x08)
            filters.append(Self.varint(uploadDate.rawValue))
        }
        if let type {
            filters.append(0x10)
            filters.append(Self.varint(type.rawValue))
        }
        if let duration {
            filters.append(0x18)
            filters.append(Self.varint(duration.rawValue))
        }

        var message = Data()
        if sortBy != .relevance {
            message.append(0x08)
            message.append(Self.varint(sortBy.rawValue))
        }
        if !filters.isEmpty {
            message.append(0x12)
            message.append(Self.varint(filters.count))
            message.append(filters)
        }

        guard !message.isEmpty else { return nil }
        return message.base64EncodedString()
    }

    /// Base-128 varint, least-significant group first.
    ///
    /// Every value used here fits in one byte, but encoding properly costs three
    /// lines and removes a trap for anyone who later adds a larger field.
    private static func varint(_ value: Int) -> Data {
        var remaining = UInt64(value)
        var out = Data()
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }
}
