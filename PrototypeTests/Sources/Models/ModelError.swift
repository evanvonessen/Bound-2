import Foundation
// Tests never make a network request or authenticate an account.
enum FriendSharingTokens {
    static func perform(_ request: URLRequest) async throws -> Data { throw BoundFriendError.unavailable }
}
