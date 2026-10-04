import XCTest

/// The local relay supplies only two dedicated Simulator peers; no friend/account is contacted.
final class PairedFriendUITests: XCTestCase {
    func testNativeFramesAcrossLocalPeer() throws {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let peer = environment["BOUND_PAIR_PEER"], ["A", "B"].contains(peer),
              let portText = environment["BOUND_PAIR_PORT"], let port = Int(portText), (1024...65535).contains(port) else {
            throw XCTSkip("Run with PrototypeTools/paired_simulators.py and two isolated Simulators")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--bound-ui-paired-transport", "--bound-ui-no-animations", "--bound-ui-screen-layout-bound", "--bound-ui-reset-layout"]
        app.launchEnvironment = ["BOUND_PAIR_PEER": peer, "BOUND_PAIR_PORT": portText]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 2) { close.tap() }
        let cell = app.collectionViews.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 30))
        cell.tap()
        let cycle = app.buttons["bound.panel-cycle"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 20))
        for _ in 0..<3 {
            if cycle.value as? String == "Friend" { break }
            cycle.tap()
        }
        XCTAssertEqual(cycle.value as? String, "Friend")
        var lastStage = ""
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            let status = try request(port: port, path: "/control/status")
            let stage = status["stage"] as? String ?? "waiting"
            if stage != lastStage {
                if stage == "done" { return }
                if stage == "background" {
                    XCUIDevice.shared.press(.home)
                    RunLoop.current.run(until: Date().addingTimeInterval(1))
                    app.activate()
                }
                if ["portrait", "landscape", "recovered"].contains(stage) {
                    XCUIDevice.shared.orientation = stage == "landscape" ? .landscapeLeft : .portrait
                    let friend = app.descendants(matching: .any).matching(identifier: "bound.friend-screen").firstMatch
                    let game = app.descendants(matching: .any).matching(identifier: "bound.game-screen").firstMatch
                    XCTAssertTrue(friend.waitForExistence(timeout: 15))
                    XCTAssertTrue(game.exists)
                    let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        !app.staticTexts["Connect a friend"].exists && friend.frame.width > 40 && friend.frame.height > 30
                    }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 20), .completed)
                    XCTAssertEqual(friend.frame.width / friend.frame.height, 1.5, accuracy: 0.02)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "Paired-\(peer)-\(stage)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                _ = try request(port: port, path: "/report-ui/" + peer, body: ["peer": peer, "stage": stage])
                lastStage = stage
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("Local paired relay did not finish within 240 seconds")
        #else
        throw XCTSkip("Local paired transport is excluded from Release")
        #endif
    }

    #if DEBUG
    private func request(port: Int, path: String, body: [String: String]? = nil) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)" + path)!)
        request.timeoutInterval = 3
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let finished = expectation(description: "Local paired relay")
        final class ResultBox: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: Result<Data, Error>?
            func set(_ value: Result<Data, Error>) { lock.lock(); stored = value; lock.unlock() }
            func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return stored }
        }
        let result = ResultBox()
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { result.set(.failure(error)) } else { result.set(.success(data ?? Data())) }
            finished.fulfill()
        }.resume()
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 5), .completed)
        guard let data = try result.get()?.get() else { throw NSError(domain: "BoundPairQA", code: 1) }
        if data.isEmpty { return [:] } // Relay acknowledgements intentionally return HTTP 204.
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    #endif
}
