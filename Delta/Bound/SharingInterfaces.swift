import Foundation

/// Cancellation is synchronous and nonblocking. Transport cancellation is best
/// effort; scheduled-clock cancellation must unregister and release its callback.
@MainActor
public protocol SharingCancellation: AnyObject {
    func cancel()
}

public enum SharingFailure: Error, Equatable, Sendable {
    case transport(String)
    case invalidClock
}

/// `send` must return promptly; completion marks the END of the send's resource
/// ownership, including cancellation cleanup. Never complete merely because a
/// cancellation request was received. A transport may ignore cancellation and
/// settle later (or never). Only one send will be handed to it by this session.
/// This seam has no SDK, token, server, audio, or emulator implementation.
@MainActor
public protocol SharingTransport: AnyObject {
    func send(
        _ frame: SharingFrame,
        completion: @escaping @MainActor (Result<Void, SharingFailure>) -> Void
    ) -> any SharingCancellation
}

/// A monotonic clock and one-shot scheduler. `now` is finite, nonnegative seconds.
/// `schedule` returns promptly and invokes on the main actor at/after the deadline.
/// Cancelling unregisters the work and releases the callback promptly. The session
/// also rejects callbacks delivered after cancellation. No polling is required.
@MainActor
public protocol SharingScheduler: AnyObject {
    var now: TimeInterval { get }
    func schedule(
        at deadline: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SharingCancellation
}
