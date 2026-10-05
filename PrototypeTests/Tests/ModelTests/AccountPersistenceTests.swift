import XCTest
import Security
@testable import Models

@MainActor
final class AccountPersistenceTests: XCTestCase {
    final class Store: BoundSessionStorage {
        var data: Data?
        var writes = 0
        var removals = 0
        var locked = false
        func read() throws -> Data? { if locked { throw BoundFriendError.unavailable }; return data }
        func write(_ data: Data) throws { if locked { throw BoundFriendError.unavailable }; self.data = data; writes += 1 }
        func remove() throws { if locked { throw BoundFriendError.unavailable }; data = nil; removals += 1 }
    }
    @MainActor final class Network {
        var requests: [URLRequest] = []
        var continuation: CheckedContinuation<BoundAuthTransport.Response, Error>?
        func perform(_ request: URLRequest) async throws -> BoundAuthTransport.Response {
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func finish(_ response: BoundAuthTransport.Response) { continuation?.resume(returning: response); continuation = nil }
        func fail() { continuation?.resume(throwing: URLError(.notConnectedToInternet)); continuation = nil }
    }
    private func token(_ owner: UUID, expires: TimeInterval = 3600) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["sub": owner.uuidString.lowercased(), "exp": Date().timeIntervalSince1970 + expires])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "fixture." + payload + ".signature"
    }
    private func saved(_ owner: UUID = UUID(), expires: TimeInterval = 3600, refresh: String = "synthetic-refresh") throws -> BoundSavedSession {
        BoundSavedSession(origin: BoundFriendAccount.origin, owner: owner, accessToken: try token(owner, expires: expires), refreshToken: refresh)
    }
    private func response(_ record: BoundSavedSession) throws -> BoundAuthTransport.Response {
        .init(data: try JSONSerialization.data(withJSONObject: ["access_token": record.accessToken, "refresh_token": record.refreshToken, "user": ["id": record.owner.uuidString]]), status: 200)
    }
    private func account(_ store: Store, network: Network = Network()) -> BoundFriendAccount {
        BoundFriendAccount(storage: store, automaticRefresh: false, configuration: { "fixture-key" }, transport: network.perform)
    }
    private func waitForRequest(_ network: Network, count: Int = 1) async {
        for _ in 0..<1000 {
            if network.requests.count >= count { return }
            await Task.yield()
        }
        XCTFail("Expected mocked auth request")
    }
    func testSignInPersistsOnlySessionAndRelaunchRestoresWithoutNetwork() async throws {
        let store = Store(); let network = Network(); let first = account(store, network: network)
        let next = try saved()
        let login = Task { await first.signIn(email: " fixture@example.invalid ", password: "test-only-password") }
        await waitForRequest(network)
        XCTAssertEqual(network.requests[0].url?.query, "grant_type=password")
        network.finish(try response(next)); await login.value
        XCTAssertEqual(first.session?.owner, next.owner)
        let bytes = try XCTUnwrap(store.data)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("test-only-password"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("fixture@example.invalid"))
        let secondNetwork = Network(); let second = account(store, network: secondNetwork)
        XCTAssertEqual(second.session?.owner, next.owner)
        try XCTUnwrap(second.session).credentials()
        await second.refreshIfNeeded()
        XCTAssertEqual(secondNetwork.requests.count, 0)
    }
    func testExpiredOfflineRestoreRetainsIdentityAndRefreshForRetry() async throws {
        let store = Store(); let original = try saved(expires: -30)
        store.data = try JSONEncoder().encode(original)
        let network = Network(); let client = account(store, network: network)
        XCTAssertEqual(client.session?.owner, original.owner)
        XCTAssertThrowsError(try client.session?.credentials())
        let operation = Task { await client.refreshIfNeeded() }
        await waitForRequest(network); network.fail(); await operation.value
        XCTAssertEqual(client.session?.owner, original.owner)
        XCTAssertEqual(try JSONDecoder().decode(BoundSavedSession.self, from: XCTUnwrap(store.data)).refreshToken, original.refreshToken)
        let retry = Task { await client.refreshIfNeeded() }
        await waitForRequest(network, count: 2)
        network.finish(try response(saved(original.owner, refresh: "rotated-refresh"))); await retry.value
        try XCTUnwrap(client.session).credentials()
        XCTAssertEqual(try JSONDecoder().decode(BoundSavedSession.self, from: XCTUnwrap(store.data)).refreshToken, "rotated-refresh")
    }
    func testConcurrentRefreshIsSingleFlightAndUpdatesExistingHolder() async throws {
        let store = Store(); let original = try saved(expires: 20)
        store.data = try JSONEncoder().encode(original)
        let network = Network(); let client = account(store, network: network)
        let holder = try XCTUnwrap(client.session)
        let one = Task { await client.refreshIfNeeded() }; let two = Task { await client.refreshIfNeeded() }
        await waitForRequest(network)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(network.requests.count, 1)
        let next = try saved(original.owner, refresh: "rotated-refresh")
        network.finish(try response(next)); await one.value; await two.value
        XCTAssertEqual(try holder.friendSharingRequest(roomID: "fixture").value(forHTTPHeaderField: "Authorization"), "Bearer " + next.accessToken)
        XCTAssertEqual(store.writes, 1)
    }
    func testSignOutRemovesPersistenceAndInvalidatesOldCopies() throws {
        let store = Store(); store.data = try JSONEncoder().encode(saved())
        let client = account(store); let holder = try XCTUnwrap(client.session)
        client.signOut()
        XCTAssertNil(store.data); XCTAssertNil(client.session)
        XCTAssertThrowsError(try holder.friendOnboardingRequest(action: "list", payload: [:]))
        XCTAssertNil(account(store).session)
    }
    func testLogoutDuringRefreshCannotRestoreLogin() async throws {
        let store = Store(); let original = try saved(expires: 20); store.data = try JSONEncoder().encode(original)
        let network = Network(); let client = account(store, network: network)
        let operation = Task { await client.refreshIfNeeded() }
        await waitForRequest(network); client.signOut()
        network.finish(try response(saved(original.owner))); await operation.value
        XCTAssertNil(client.session); XCTAssertNil(store.data)
    }
    func testLogoutDuringSignInCannotRestoreLogin() async throws {
        let store = Store(); let network = Network(); let client = account(store, network: network)
        let operation = Task { await client.signIn(email: "fixture@example.invalid", password: "fixture") }
        await waitForRequest(network); client.signOut()
        network.finish(try response(saved())); await operation.value
        XCTAssertNil(client.session); XCTAssertNil(store.data); XCTAssertFalse(client.busy)
    }
    func testAccountSwitchInvalidatesOldHolderButNotUnrelatedAccount() async throws {
        let store = Store(); let old = try saved(); store.data = try JSONEncoder().encode(old)
        let network = Network(); let client = account(store, network: network); let holder = try XCTUnwrap(client.session)
        let unrelatedStore = Store(); unrelatedStore.data = try JSONEncoder().encode(saved())
        let unrelated = account(unrelatedStore); let unrelatedHolder = try XCTUnwrap(unrelated.session)
        let next = try saved()
        let login = Task { await client.signIn(email: "new@example.invalid", password: "fixture") }
        await waitForRequest(network); network.finish(try response(next)); await login.value
        XCTAssertEqual(client.session?.owner, next.owner)
        XCTAssertThrowsError(try holder.credentials()); XCTAssertNoThrow(try unrelatedHolder.credentials())
    }
    func testRevokedRefreshClearsLoginButTransientServerFailuresDoNot() async throws {
        for code in ["refresh_token_not_found", "refresh_token_already_used", "session_expired", "session_not_found", "user_banned"] {
            let store = Store(); store.data = try JSONEncoder().encode(saved(expires: -20))
            let network = Network(); let client = account(store, network: network)
            let operation = Task { await client.refreshIfNeeded() }; await waitForRequest(network)
            network.finish(.init(data: try JSONSerialization.data(withJSONObject: ["code": code]), status: 400)); await operation.value
            XCTAssertNil(client.session); XCTAssertNil(store.data)
        }
        for status in [401, 403, 429, 500, 503] {
            let store = Store(); store.data = try JSONEncoder().encode(saved(expires: -20))
            let network = Network(); let client = account(store, network: network)
            let operation = Task { await client.refreshIfNeeded() }; await waitForRequest(network)
            network.finish(.init(data: Data("{}".utf8), status: status)); await operation.value
            XCTAssertNotNil(client.session); XCTAssertNotNil(store.data)
        }
    }
    func testOldRefreshCannotOverwriteNewAccount() async throws {
        let store = Store(); let old = try saved(expires: 20); store.data = try JSONEncoder().encode(old)
        let network = Network(); let next = try saved(); let nextResponse = try response(next)
        let client = BoundFriendAccount(storage: store, automaticRefresh: false, configuration: { "fixture-key" }, transport: { request in
            if request.url?.query == "grant_type=password" { return nextResponse }
            return try await network.perform(request)
        })
        let holder = try XCTUnwrap(client.session)
        let refresh = Task { await client.refreshIfNeeded() }; await waitForRequest(network)
        await client.signIn(email: "new@example.invalid", password: "fixture")
        network.finish(try response(saved(old.owner))); await refresh.value
        XCTAssertEqual(client.session?.owner, next.owner)
        XCTAssertEqual(try JSONDecoder().decode(BoundSavedSession.self, from: XCTUnwrap(store.data)).owner, next.owner)
        XCTAssertThrowsError(try holder.credentials())
    }
    func testExplicitLogoutFailureIsRetriedBeforeNewLogin() async throws {
        let store = Store(); store.data = try JSONEncoder().encode(saved())
        let client = account(store); let holder = try XCTUnwrap(client.session)
        store.locked = true; client.signOut()
        XCTAssertNil(client.session); XCTAssertThrowsError(try holder.credentials())
        XCTAssertTrue(client.status.contains("Could not remove"))
        store.locked = false; await client.refreshIfNeeded()
        XCTAssertNil(store.data); XCTAssertNil(client.session)
    }
    func testLockedKeychainRestoreRetriesWithoutDeleting() async throws {
        let store = Store(); let original = try saved(); store.data = try JSONEncoder().encode(original); store.locked = true
        let client = account(store)
        XCTAssertNil(client.session); XCTAssertEqual(store.removals, 0)
        store.locked = false; await client.refreshIfNeeded()
        XCTAssertEqual(client.session?.owner, original.owner)
    }
    func testAutomaticRefreshRenewsNearExpiryOnRestore() async throws {
        let store = Store(); let original = try saved(expires: 20); store.data = try JSONEncoder().encode(original)
        let network = Network()
        let client = BoundFriendAccount(storage: store, automaticRefresh: true, configuration: { "fixture-key" }, transport: network.perform)
        await waitForRequest(network)
        XCTAssertEqual(network.requests.count, 1)
        network.finish(try response(saved(original.owner)))
        for _ in 0..<1000 { if store.writes > 0 { break }; await Task.yield() }
        XCTAssertEqual(store.writes, 1); XCTAssertGreaterThan(try XCTUnwrap(client.session).expiresAt.timeIntervalSinceNow, 3000)
        client.signOut()
    }
    func testRotatedTokenSurvivesTemporarySaveFailureAndRetriesWithoutRefreshingAgain() async throws {
        let store = Store(); let original = try saved(expires: 20); store.data = try JSONEncoder().encode(original)
        let network = Network(); let client = account(store, network: network)
        let operation = Task { await client.refreshIfNeeded() }; await waitForRequest(network)
        store.locked = true; let next = try saved(original.owner, refresh: "rotated-refresh")
        network.finish(try response(next)); await operation.value
        XCTAssertEqual(try client.session?.friendSharingRequest(roomID: "fixture").value(forHTTPHeaderField: "Authorization"), "Bearer " + next.accessToken)
        store.locked = false; await client.refreshIfNeeded()
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(BoundSavedSession.self, from: XCTUnwrap(store.data)).refreshToken, next.refreshToken)
    }
    func testCorruptStoredSessionClearsButConfigurationFailureDoesNot() throws {
        let corrupt = Store(); corrupt.data = Data("not a session".utf8)
        XCTAssertNil(account(corrupt).session); XCTAssertNil(corrupt.data)
        let store = Store(); store.data = try JSONEncoder().encode(saved())
        let client = BoundFriendAccount(storage: store, automaticRefresh: false, configuration: { throw BoundFriendError.unavailable })
        XCTAssertNil(client.session); XCTAssertNotNil(store.data); XCTAssertEqual(store.removals, 0)
    }
    func testWrongOwnerOnRefreshSignsOutWithoutCrossAccountCredentials() async throws {
        let store = Store(); store.data = try JSONEncoder().encode(saved(expires: 20))
        let network = Network(); let client = account(store, network: network); let holder = try XCTUnwrap(client.session)
        let operation = Task { await client.refreshIfNeeded() }; await waitForRequest(network)
        network.finish(try response(saved())); await operation.value
        XCTAssertNil(client.session); XCTAssertNil(store.data); XCTAssertThrowsError(try holder.credentials())
    }
    func testFailedPersistenceDoesNotPublishUnsavedLogin() async throws {
        let store = Store(); let network = Network(); let client = account(store, network: network)
        let login = Task { await client.signIn(email: "fixture@example.invalid", password: "fixture") }
        await waitForRequest(network); store.locked = true
        network.finish(try response(saved())); await login.value
        XCTAssertNil(client.session); XCTAssertNil(store.data)
    }
    func testKeychainPolicyAtomicUpdateAndErrorHandling() throws {
        var updated = false; var added = false; var deleted = false
        var calls = BoundKeychainSessionStorage.Calls()
        calls.update = { query, attributes in
            let query = query as NSDictionary; let attributes = attributes as NSDictionary
            XCTAssertEqual(query[kSecClass] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(query[kSecAttrAccount] as? String, BoundFriendAccount.origin)
            XCTAssertEqual(query[kSecAttrSynchronizable] as? Bool, false)
            XCTAssertEqual(attributes[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            updated = true; return errSecItemNotFound
        }
        calls.add = { attributes, _ in
            let attributes = attributes as NSDictionary
            XCTAssertEqual(attributes[kSecValueData] as? Data, Data("synthetic".utf8))
            XCTAssertEqual(attributes[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            added = true; return errSecSuccess
        }
        calls.copy = { _, output in output?.pointee = Data("synthetic".utf8) as CFData; return errSecSuccess }
        calls.delete = { _ in deleted = true; return errSecSuccess }
        let suite = "BoundAuthTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = BoundKeychainSessionStorage(calls: calls, defaults: defaults)
        try keychain.write(Data("synthetic".utf8)); XCTAssertTrue(updated); XCTAssertTrue(added)
        XCTAssertEqual(try keychain.read(), Data("synthetic".utf8)); try keychain.remove(); XCTAssertTrue(deleted)
        try keychain.write(Data("synthetic".utf8))
        calls.copy = { _, _ in errSecInteractionNotAllowed }; calls.update = { _, _ in errSecInteractionNotAllowed }; calls.delete = { _ in errSecInteractionNotAllowed }
        let locked = BoundKeychainSessionStorage(calls: calls, defaults: defaults)
        XCTAssertThrowsError(try locked.read())
        // Logout's non-secret marker survives a failed delete and prevents silent restoration.
        XCTAssertThrowsError(try locked.write(Data())); XCTAssertThrowsError(try locked.remove())
        XCTAssertNil(try BoundKeychainSessionStorage(calls: calls, defaults: defaults).read())
    }
}
