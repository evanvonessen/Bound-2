import XCTest
import CryptoKit
@testable import Delta

final class SourceAndLicenseTests: XCTestCase {
    func testBundledAGPLMatchesUnmodifiedRootCopying() throws {
        let data = try XCTUnwrap(BoundSourceNotices.Document.agpl.data())
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // SHA-256 of the exact upstream root COPYING, including its final newline.
        XCTAssertEqual(hash, "4df3c306dddaaf4baffdff5ca820cc679ac8cd6dc263c6a74517783e42fa7a3b")
        XCTAssertTrue(try XCTUnwrap(BoundSourceNotices.Document.agpl.text()).contains("GNU AFFERO GENERAL PUBLIC LICENSE"))
    }
    func testSourceAvailabilityAndVersionDescribeCurrentBundle() throws {
        XCTAssertEqual(BoundSourceNotices.availability, "Bound 2 source, build instructions, and modification notices are available in its source repository.")
        XCTAssertEqual(BoundSourceNotices.sourceRepository.absoluteString, "https://github.com/evanvonessen/Bound-2")
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertEqual(BoundSourceNotices.version(), "\(version) (\(build))")
    }
    func testBundledModificationAndDependencyNoticesArePresent() throws {
        for document in [BoundSourceNotices.Document.modifications, .dependencies] {
            let text = try XCTUnwrap(document.text(), document.resource)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
