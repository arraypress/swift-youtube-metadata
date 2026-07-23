//
//  JSONNav.swift
//  YouTubeChannel
//
//  Created by David Sherlock on 2025.
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

    /// Returns every array in the tree (depth-first, pre-order) that contains
    /// at least one element satisfying `elementContains`.
    ///
    /// Used to locate the grid array that holds the video items so its sibling
    /// continuation token can be read without picking up unrelated tokens (the
    /// About panel and header carry their own continuations).
    static func arrays(in obj: Any?, whereElement elementContains: (Any) -> Bool) -> [[Any]] {
        var results: [[Any]] = []
        collectArrays(in: obj, whereElement: elementContains, into: &results)
        return results
    }

    private static func collectArrays(
        in obj: Any?,
        whereElement elementContains: (Any) -> Bool,
        into results: inout [[Any]]
    ) {
        if let dict = obj as? [String: Any] {
            for value in dict.values {
                collectArrays(in: value, whereElement: elementContains, into: &results)
            }
        } else if let array = obj as? [Any] {
            if array.contains(where: elementContains) {
                results.append(array)
            }
            for value in array {
                collectArrays(in: value, whereElement: elementContains, into: &results)
            }
        }
    }
}
