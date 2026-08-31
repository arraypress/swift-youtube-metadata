//
//  SupportTests.swift
//
//  The formatting rules pinned directly — no model constructed.
//

import XCTest
@testable import YouTubeTranscript

final class SupportTests: XCTestCase {

    func testTimestampFormatting() {
        XCTAssertEqual(Formatting.timestamp(seconds: 0), "0:00")
        XCTAssertEqual(Formatting.timestamp(seconds: 3599), "59:59")
        XCTAssertEqual(Formatting.timestamp(seconds: 3930), "1:05:30")
    }

    func testCountFormattingWithPinnedLocale() {
        XCTAssertEqual(Formatting.count(1_500_000_000, locale: Locale(identifier: "en_US")), "1,500,000,000")
    }
}
