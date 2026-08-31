//
//  Protobuf.swift
//  YouTubeSearch
//
//  Created by David Sherlock on 2026.
//
//  The one piece of wire encoding the search filters need, alone and
//  pinned directly.
//

import Foundation

/// Minimal protobuf primitives for the `sp` parameter.
enum Protobuf {

    /// Base-128 varint, least-significant group first.
    ///
    /// Every value used here fits in one byte, but encoding properly costs three
    /// lines and removes a trap for anyone who later adds a larger field.
    static func varint(_ value: Int) -> Data {
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
