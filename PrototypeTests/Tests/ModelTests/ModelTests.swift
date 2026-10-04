import Foundation
import XCTest
@testable import Models
final class ModelTests: XCTestCase {
    func testGateDisabledAndSingleFlight() throws {
        let gate = BoundFrameCaptureGate()
        XCTAssertNil(gate.begin(now: 1))
        gate.configure(enabled: true)
        let epoch = try XCTUnwrap(gate.begin(now: 1))
        XCTAssertNil(gate.begin(now: 100))
        XCTAssertTrue(gate.finish(epoch: epoch))
        XCTAssertNil(gate.begin(now: 1.01))
        XCTAssertNotNil(gate.begin(now: 1.034))
    }
    func testCaptureCannotEscapeDisableOrRebind() throws {
        let gate = BoundFrameCaptureGate(); gate.configure(enabled: true)
        let epoch = try XCTUnwrap(gate.begin(now: 1))
        gate.configure(enabled: false); gate.configure(enabled: true)
        XCTAssertNil(gate.begin(now: 2))
        XCTAssertFalse(gate.finish(epoch: epoch))
        XCTAssertNotNil(gate.begin(now: 2))
    }
    func testSimultaneousCallbacksAdmitOnlyOne() {
        let gate = BoundFrameCaptureGate(); gate.configure(enabled: true)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in _ = gate.begin(now: 1) }
        XCTAssertNil(gate.begin(now: 10))
    }
    func testCaptureMaintainsCadenceUnderSourceJitterAndDropsStalledSlots() throws {
        let gate = BoundFrameCaptureGate(); gate.configure(enabled: true)
        var admitted = 0
        for index in 0..<600 {
            let time = 10 + Double(index) / 60 + sin(Double(index) * 0.7) * 0.0004
            if let epoch = gate.begin(now: time) { admitted += 1; XCTAssertTrue(gate.finish(epoch: epoch)) }
        }
        XCTAssertTrue((299...301).contains(admitted), "Expected about 30 samples/s, got \(admitted) in 10s")
        let epoch = try XCTUnwrap(gate.begin(now: 100)); XCTAssertTrue(gate.finish(epoch: epoch))
        XCTAssertNil(gate.begin(now: 100)) // No catch-up after a long stall.
    }
    func testNotesArePartitionedAndAtomic() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BoundNotesStore(directory: dir)
        XCTAssertEqual(try store.read(game: "abc"), "")
        try store.write("first", game: "abc"); try store.write("other", game: "def")
        try store.write("replacement", game: "abc")
        XCTAssertEqual(try store.read(game: "abc"), "replacement")
        XCTAssertEqual(try store.read(game: "def"), "other")
    }
    func testInvalidAndOversizeWritesKeepExistingNotes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BoundNotesStore(directory: dir); try store.write("kept", game: "abc")
        XCTAssertThrowsError(try store.write(String(repeating: "é", count: 8001), game: "abc"))
        XCTAssertThrowsError(try store.write("bad", game: "../escape"))
        XCTAssertEqual(try store.read(game: "abc"), "kept")
        try Data(repeating: 65, count: 16001).write(to: try XCTUnwrap(store.url(game: "large")))
        XCTAssertThrowsError(try store.read(game: "large"))
    }
}
extension ModelTests {
    private func token(owner: UUID, expiry: TimeInterval) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: ["sub": owner.uuidString.lowercased(), "exp": expiry])
        let body = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "fixture." + body + ".signature"
    }
    func testSessionRejectsExpiredAndWrongOwner() throws {
        let owner = UUID()
        XCTAssertThrowsError(try AppCloudSession(owner: owner, key: "fixture", token: token(owner: owner, expiry: Date().timeIntervalSince1970 - 1)))
        XCTAssertThrowsError(try AppCloudSession(owner: UUID(), key: "fixture", token: token(owner: owner, expiry: Date().timeIntervalSince1970 + 100)))
    }
    func testFriendRequestsKeepExistingEndpointsAndRedactSession() throws {
        let owner = UUID(); let access = try token(owner: owner, expiry: Date().timeIntervalSince1970 + 100)
        let session = try AppCloudSession(owner: owner, key: "fixture-key", token: access)
        let room = UUID().uuidString.lowercased()
        let request = try session.friendSharingRequest(roomID: room)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/functions/v1/agora-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + access)
        XCTAssertFalse(session.description.contains(access))
        XCTAssertFalse(session.debugDescription.contains("fixture-key"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(json, ["roomID": room])
        let invite = try session.friendOnboardingRequest(action: "list", payload: [:])
        XCTAssertEqual(invite.url?.path, "/rest/v1/rpc/cup050_friends")
    }
}
