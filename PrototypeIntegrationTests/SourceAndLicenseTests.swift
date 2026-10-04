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
    func testBundledInventoryAndFontNoticeMatchCurrentSources() throws {
        let inventory = try XCTUnwrap(BoundSourceNotices.Document.dependencies.data())
        let digest = SHA256.hash(data: inventory).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "5f31d52fbdde9315e579e6a217621fc90ab88b9b75cb1684cf2c30982a4bd685")
        let url = try XCTUnwrap(Bundle.main.url(forResource: "EARLY-GAMEBOY-LICENSE", withExtension: "txt"))
        let notice = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(notice.contains("Copyright LDEJRuff 2012"))
        XCTAssertTrue(notice.contains("Attribution-ShareAlike 3.0 Unported"))
        let fontURL = try XCTUnwrap(Bundle.main.url(forResource: "Early GameBoy", withExtension: "ttf"))
        let fontHash = SHA256.hash(data: try Data(contentsOf: fontURL)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(fontHash, "fb84ef1d7f837c5993b80b9a3319284dc49883394d0def0c9c999b51b4683d13")
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
