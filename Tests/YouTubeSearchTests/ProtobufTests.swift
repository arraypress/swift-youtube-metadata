//
//  ProtobufTests.swift
//
//  The varint rule pinned directly.
//

import XCTest
@testable import YouTubeSearch

final class ProtobufTests: XCTestCase {

    func testVarintEncoding() {
        XCTAssertEqual(Array(Protobuf.varint(1)), [0x01])
        XCTAssertEqual(Array(Protobuf.varint(300)), [0xAC, 0x02])
    }
}
