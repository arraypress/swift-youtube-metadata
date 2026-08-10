//
//  JSONNav.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//
//  Self-contained copy — this target intentionally shares no code with the
//  other modules in the package so each stays independently usable.
//

import Foundation

/// Lightweight helpers for navigating YouTube's deeply-nested, loosely-typed
/// InnerTube JSON (parsed as `[String: Any]` / `[Any]`).
///
/// YouTube's response shapes change often and bury the same renderer at
/// different depths, so a recursive "find by key" approach is far more
/// resilient than hard-coded key paths.
enum JSONNav {

    /// Returns the first value found for `key` anywhere in the object tree
    /// (depth-first, pre-order).
    static func first(_ key: String, in obj: Any?) -> Any? {
        guard let obj else { return nil }
        if let dict = obj as? [String: Any] {
            if let hit = dict[key] { return hit }
            for value in dict.values {
                if let found = first(key, in: value) { return found }
            }
        } else if let array = obj as? [Any] {
            for value in array {
                if let found = first(key, in: value) { return found }
            }
        }
        return nil
    }

    /// Convenience: the first `String` found for `key`.
    static func string(_ key: String, in obj: Any?) -> String? {
        first(key, in: obj) as? String
    }

    /// Returns every dictionary in the tree that contains `key`, in depth-first
    /// pre-order.
    ///
    /// Search results are spread across several `itemSectionRenderer` sections —
    /// ads, "people also watched" shelves, and the results themselves — so
    /// collecting every `videoRenderer` wherever it sits is far more robust than
    /// walking one hard-coded path that YouTube reshuffles regularly.
    static func all(_ key: String, in obj: Any?) -> [[String: Any]] {
        var results: [[String: Any]] = []
        collect(key, in: obj, into: &results)
        return results
    }

    private static func collect(_ key: String, in obj: Any?, into results: inout [[String: Any]]) {
        if let dict = obj as? [String: Any] {
            if let hit = dict[key] as? [String: Any] {
                results.append(hit)
            }
            for value in dict.values {
                collect(key, in: value, into: &results)
            }
        } else if let array = obj as? [Any] {
            for value in array {
                collect(key, in: value, into: &results)
            }
        }
    }

    /// Flattens YouTube's `{ "runs": [{ "text": … }] }` / `{ "simpleText": … }`
    /// text containers into a plain string.
    ///
    /// Both shapes appear interchangeably for the same field depending on
    /// endpoint and client version, so every text read goes through here.
    static func text(_ obj: Any?) -> String? {
        guard let dict = obj as? [String: Any] else { return nil }

        if let simple = dict["simpleText"] as? String, !simple.isEmpty {
            return simple
        }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}
