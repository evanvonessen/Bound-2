import Foundation
import Combine

/// Uses the existing Bound friend service; credentials live only in this app session.
struct AppCloudSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let owner: UUID
    let expiresAt: Date
    private let key: String
    private let token: String
    init(owner: UUID, key: String, token: String) throws {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }), token.utf8.count <= 16384 else { throw BoundFriendError.signIn }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: encoded),
              let claims = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let expiry = claims["exp"] as? Double, expiry.isFinite, expiry > Date().timeIntervalSince1970,
              claims["sub"] as? String == owner.uuidString.lowercased() else { throw BoundFriendError.signIn }
        self.owner = owner; self.key = key; self.token = token; expiresAt = Date(timeIntervalSince1970: expiry)
    }
    func credentials() throws {
        guard expiresAt > Date() else { throw BoundFriendError.signIn }
    }
    private func request(path: String, body: [String: Any]) throws -> URLRequest {
        try credentials()
        var request = URLRequest(url: URL(string: BoundFriendAccount.origin + path)!)
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    func friendOnboardingRequest(action: String, payload: [String: String]) throws -> URLRequest {
        try request(path: "/rest/v1/rpc/cup050_friends", body: ["action": action, "payload": payload])
    }
    func friendSharingRequest(roomID: String) throws -> URLRequest {
        try request(path: "/functions/v1/agora-token", body: ["roomID": roomID])
    }
    var description: String { "AppCloudSession(redacted)" }
    var debugDescription: String { description }
}

enum BoundFriendError: Error { case signIn, unavailable }

@MainActor
final class BoundFriendAccount: ObservableObject {
    nonisolated static let origin = "https://qevnxhngdtlyihhmvnjv.supabase.co"
    @Published private(set) var session: AppCloudSession?
    @Published private(set) var busy = false
    @Published private(set) var status = "Sign in with your existing Bound account."
    private var generation = UUID()
    func signIn(email: String, password: String) async {
        guard !busy else { return }
        let run = UUID(); generation = run; busy = true
        defer { if generation == run { busy = false } }
        do {
            guard let url = Bundle.main.url(forResource: "cloud-configuration", withExtension: "json"),
                  let config = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  config["origin"] as? String == Self.origin,
                  let key = config["publishableKey"] as? String, key.hasPrefix("sb_publishable_") else { throw BoundFriendError.unavailable }
            var request = URLRequest(url: URL(string: Self.origin + "/auth/v1/token?grant_type=password")!)
            request.httpMethod = "POST"; request.timeoutInterval = 10
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
            let data = try await FriendSharingTokens.perform(request)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["access_token"] as? String, let user = object["user"] as? [String: Any],
                  let id = user["id"] as? String, let owner = UUID(uuidString: id) else { throw BoundFriendError.signIn }
            let next = try AppCloudSession(owner: owner, key: key, token: token)
            guard generation == run, !Task.isCancelled else { return }
            session = next; status = "Signed in."
        } catch {
            guard generation == run else { return }
            status = "Could not sign in. Check your account and connection."
        }
    }
    func signOut() { generation = UUID(); session = nil; busy = false; status = "Signed out." }
}
