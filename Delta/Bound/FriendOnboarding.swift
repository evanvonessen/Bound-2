import SwiftUI
import UIKit

struct FriendRoom: Decodable, Equatable, Identifiable, Sendable {
    let roomID: String
    let displayName: String
    var id: String { roomID }
    var valid: Bool {
        UUID(uuidString: roomID) != nil && !displayName.isEmpty && displayName.count <= 40 &&
        !displayName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
struct FriendResponse: Decodable, Sendable {
    let ok: Bool
    var code: String? = nil
    var room: FriendRoom? = nil
    var rooms: [FriendRoom]? = nil
}

@MainActor
final class FriendOnboarding: ObservableObject {
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var message = "Sign in to add a friend."
    @Published private(set) var rooms: [FriendRoom] = []
    @Published private(set) var selected: FriendRoom?
    @Published private(set) var inviteCode: String?
    @Published private(set) var managesFlow = false
    private var permitsRTC = true
    private var ownerID: UUID?
    private var observation: FriendSharingTimer?
    private var reusedSession: (() -> AppCloudSession?)?
    private weak var sharing: FriendSharingSession?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let call: @MainActor (AppCloudSession, String, [String: String]) async throws -> FriendResponse

    init(call: @escaping @MainActor (AppCloudSession, String, [String: String]) async throws -> FriendResponse = { session, action, payload in
        let bytes = try await FriendSharingTokens.perform(try session.friendOnboardingRequest(action: action, payload: payload))
        let response = try JSONDecoder().decode(FriendResponse.self, from: bytes)
        guard response.ok else { throw FriendSharingTokenError.unavailable }
        return response
    }) { self.call = call }

    isolated deinit { task?.cancel(); observation?.cancel() }
    func open(sharing: FriendSharingSession, existing: (() -> AppCloudSession?)?) {
        self.sharing = sharing; reusedSession = existing
        if !permitsRTC {
            managesFlow = true
            sharing.configureAuthenticatedRoom(nil, identity: { nil })
        }
        if observation == nil {
            observation = FriendSharingTimer(after: 1, repeating: true) { [weak self] in self?.synchronizeAccount() }
        }
        synchronizeAccount()
    }
    /// Reads only the current account owner; no password grant, refresh or network
    /// work occurs here. Login may finish after Saves is opened or dismissed.
    func synchronizeAccount() {
        let candidate = reusedSession?()
        let current = candidate.flatMap { (try? $0.credentials()) == nil ? nil : $0 }
        guard current?.owner != ownerID else { return }
        let hadAccount = ownerID != nil
        close(); ownerID = nil; signedIn = false; rooms = []; selected = nil
        if hadAccount || current != nil || managesFlow {
            managesFlow = true
            sharing?.configureAuthenticatedRoom(nil, identity: { [weak self] in self?.sharingIdentity() })
        }
        guard let current else { message = "Sign in above to add a friend."; return }
        ownerID = current.owner; signedIn = true; message = "Choose a friend or exchange an invite."
        refresh()
    }
    func close() { generation = UUID(); task?.cancel(); task = nil; busy = false; inviteCode = nil }
    private func sharingIdentity() -> AppCloudSession? { permitsRTC ? currentIdentity() : nil }
    static func mockNamespace(arguments: [String]) -> UUID? {
        #if DEBUG && targetEnvironment(simulator)
        guard arguments.contains("--friend-onboarding-mock"), let index = arguments.firstIndex(of: "--preservation-test"),
              arguments.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: arguments[index + 1])
        #else
        return nil
        #endif
    }
    static func forUI(arguments: [String] = ProcessInfo.processInfo.arguments) -> FriendOnboarding {
        #if DEBUG && targetEnvironment(simulator)
        guard let namespace = mockNamespace(arguments: arguments) else { return FriendOnboarding() }
        let fixture = FriendOnboardingFixture(namespace: namespace)
        let model = FriendOnboarding(call: { _, action, payload in try fixture.call(action, payload: payload) })
        model.permitsRTC = false // Every mock action is inert, including Start sharing.
        return model
        #else
        return FriendOnboarding()
        #endif
    }
    func currentIdentity() -> AppCloudSession? {
        guard let ownerID, let current = reusedSession?(), current.owner == ownerID,
              (try? current.credentials()) != nil else { return nil }
        return current
    }
    func signOut() {
        close(); ownerID = nil; signedIn = false; managesFlow = true
        rooms = []; selected = nil; message = "Sign in above to add a friend."
        sharing?.configureAuthenticatedRoom(nil, identity: { nil })
    }
    func select(_ room: FriendRoom) {
        guard !busy, room.valid, rooms.contains(room), currentIdentity() != nil else { return }
        selected = room
        sharing?.configureAuthenticatedRoom(room.roomID, identity: { [weak self] in self?.sharingIdentity() })
        message = "Ready to share with \(room.displayName)."
    }
    func refresh() { request("list", payload: [:]) }
    func create(name: String) { request("create", payload: ["displayName": name.trimmingCharacters(in: .whitespacesAndNewlines)]) }
    func accept(code: String, name: String) { request("accept", payload: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), "displayName": name.trimmingCharacters(in: .whitespacesAndNewlines)]) }
    func remove(_ room: FriendRoom) {
        guard !busy else { return }
        if selected?.roomID == room.roomID { selected = nil; sharing?.configureAuthenticatedRoom(nil, identity: { [weak self] in self?.sharingIdentity() }) }
        request("remove", payload: ["roomID": room.roomID])
    }
    private func request(_ action: String, payload: [String: String]) {
        guard !busy else { return }
        guard let identity = currentIdentity() else { signOut(); return }
        busy = true; message = "Updating friends…"
        let run = generation; let call = call
        task = Task { [weak self] in
            do {
                let response = try await call(identity, action, payload)
                try Task.checkCancellation()
                guard let self, self.generation == run else { return }
                guard self.currentIdentity()?.owner == identity.owner else { self.signOut(); return }
                guard response.ok else { throw FriendSharingTokenError.unavailable }
                if action == "list" {
                    guard let rooms = response.rooms, rooms.count <= 20, rooms.allSatisfy(\.valid), Set(rooms.map(\.roomID)).count == rooms.count else { throw FriendSharingTokenError.unavailable }
                    self.rooms = rooms
                    if let selected = self.selected, !rooms.contains(where: { $0.roomID == selected.roomID }) {
                        self.selected = nil; self.sharing?.configureAuthenticatedRoom(nil, identity: { [weak self] in self?.sharingIdentity() })
                    }
                } else if action == "create" {
                    guard let code = response.code, code.range(of: "^[0-9A-F]{16}$", options: .regularExpression) != nil else { throw FriendSharingTokenError.unavailable }
                    self.inviteCode = code
                } else if action == "accept" {
                    guard let room = response.room, room.valid else { throw FriendSharingTokenError.unavailable }
                    self.rooms.removeAll { $0.roomID == room.roomID }; self.rooms.append(room); self.busy = false; self.select(room)
                } else if action == "remove" {
                    self.rooms.removeAll { $0.roomID == payload["roomID"] }
                    if self.selected?.roomID == payload["roomID"] {
                        self.selected = nil
                        self.sharing?.configureAuthenticatedRoom(nil, identity: { [weak self] in self?.sharingIdentity() })
                    }
                }
                self.busy = false; self.task = nil; self.message = ""
            } catch {
                guard let self, self.generation == run else { return }
                self.busy = false; self.task = nil; self.message = "Could not update friends. Check the code or try again."
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
private final class FriendOnboardingFixture {
    let namespace: UUID
    var rooms: [FriendRoom] = []
    init(namespace: UUID) { self.namespace = namespace }
    func call(_ action: String, payload: [String: String]) throws -> FriendResponse {
        switch action {
        case "list": return .init(ok: true, rooms: rooms)
        case "create": return .init(ok: true, code: "0123456789ABCDEF")
        case "accept":
            guard payload["code"] == "0123456789ABCDEF" else { throw FriendSharingTokenError.unavailable }
            let room = FriendRoom(roomID: namespace.uuidString.lowercased(), displayName: "Fixture Friend")
            rooms = [room]; return .init(ok: true, room: room)
        case "remove": rooms = []; return .init(ok: true)
        default: throw FriendSharingTokenError.unavailable
        }
    }
}

#endif
