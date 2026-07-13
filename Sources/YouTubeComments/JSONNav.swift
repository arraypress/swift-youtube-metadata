//
//  JSONNav.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
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

    /// Returns every value found for `key` anywhere in the object tree,
    /// in depth-first pre-order. Does not descend into a matched value.
    static func all(_ key: String, in obj: Any?) -> [Any] {
        var results: [Any] = []
        collect(key, in: obj, into: &results)
        return results
    }

    private static func collect(_ key: String, in obj: Any?, into results: inout [Any]) {
        if let dict = obj as? [String: Any] {
            for (k, value) in dict {
                if k == key {
                    results.append(value)
                } else {
                    collect(key, in: value, into: &results)
                }
            }
        } else if let array = obj as? [Any] {
            for value in array {
                collect(key, in: value, into: &results)
            }
        }
    }

    /// Convenience: the first `String` found for `key`.
    static func string(_ key: String, in obj: Any?) -> String? {
        first(key, in: obj) as? String
    }

    /// Returns the first dictionary in the tree (depth-first, pre-order) that
    /// satisfies `predicate`.
    static func firstDict(in obj: Any?, where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        if let dict = obj as? [String: Any] {
            if predicate(dict) { return dict }
            for value in dict.values {
                if let found = firstDict(in: value, where: predicate) { return found }
            }
        } else if let array = obj as? [Any] {
            for value in array {
                if let found = firstDict(in: value, where: predicate) { return found }
            }
        }
        return nil
    }
}
