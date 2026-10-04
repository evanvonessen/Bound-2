import Foundation

public struct SharingSessionToken: Equatable, Sendable {
    fileprivate let id = UUID()
    fileprivate init() {}
}

public enum SharingSessionState: Equatable, Sendable {
    case stopped
    case running
    case backgrounded
    case failed(SharingFailure)
}

public enum SharingSessionError: Error, Equatable, Sendable {
    case invalidPublicationInterval
    case backgrounded
    case staleSession
    case inactiveSession
    case nonIncreasingSequence
    case nonIncreasingCaptureTime
}

/// Synchronous latest-frame handoff. Call on the main actor, without spawning a
/// Task per produced frame. There are no internal Tasks or polling loops.
///
/// Across ALL generations: at most one handed-off send, one pending frame, and one
/// scheduled wakeup. Stop clears pending work and requests cancellation without
/// waiting. A stuck send continues to occupy the sole send slot across restarts.
@MainActor
public final class SharingSession {
    public private(set) var state: SharingSessionState = .stopped
    public private(set) var currentToken: SharingSessionToken?

    private struct Flight {
        let id: UUID
        var cancellation: (any SharingCancellation)?
        var cancellationRequested = false
    }
    private struct Wakeup {
        let id: UUID
        var cancellation: (any SharingCancellation)?
        // Keep ownership until registration AND cancellation cleanup return.
        var isFinished = false
    }

    private let transport: any SharingTransport
    private let scheduler: any SharingScheduler
    private let interval: TimeInterval
    private var pending: SharingFrame?
    private var flight: Flight?
    private var wakeup: Wakeup?
    private var isPumping = false
    private var pumpRequested = false
    private var lastAccepted: (sequence: UInt64, capturedAt: TimeInterval)?
    private var lastClockReading: TimeInterval?
    // Keep pacing across stop/restart so reconnects cannot create publication bursts.
    private var nextSendAt: TimeInterval = 0

    public init(
        transport: any SharingTransport,
        scheduler: any SharingScheduler,
        minimumPublicationInterval: TimeInterval
    ) throws {
        guard minimumPublicationInterval.isFinite, minimumPublicationInterval > 0 else {
            throw SharingSessionError.invalidPublicationInterval
        }
        self.transport = transport
        self.scheduler = scheduler
        self.interval = minimumPublicationInterval
    }

    /// An explicit foreground start. Repeated starts while running are idempotent.
    /// Capture this token at the producer/callback origin; never substitute a newer
    /// currentToken when delivering old work.
    @discardableResult
    public func start() throws -> SharingSessionToken {
        guard state != .backgrounded else { throw SharingSessionError.backgrounded }
        if state == .running, let currentToken { return currentToken }
        let token = SharingSessionToken()
        currentToken = token
        lastAccepted = nil
        state = .running
        return token
    }

    public func submit(_ frame: SharingFrame, for token: SharingSessionToken) throws {
        guard currentToken == token else { throw SharingSessionError.staleSession }
        guard state == .running else { throw SharingSessionError.inactiveSession }
        if let lastAccepted {
            guard frame.sequence > lastAccepted.sequence else {
                throw SharingSessionError.nonIncreasingSequence
            }
            guard frame.capturedAt > lastAccepted.capturedAt else {
                throw SharingSessionError.nonIncreasingCaptureTime
            }
        }
        lastAccepted = (frame.sequence, frame.capturedAt)
        pending = frame
        pump()
    }

    public func stop() {
        // Background suspension must not be undone by a subsequent stop/start pair.
        invalidate(to: state == .backgrounded ? .backgrounded : .stopped, keepToken: false)
    }

    public func enterBackground() {
        invalidate(to: .backgrounded, keepToken: false)
    }

    /// Foregrounding leaves publication stopped; the owner explicitly starts again.
    public func enterForeground() {
        if state == .backgrounded { state = .stopped }
    }

    /// Token-gated asynchronous transport failure notification.
    public func reportFailure(_ failure: SharingFailure, for token: SharingSessionToken) {
        guard currentToken == token, state == .running else { return }
        invalidate(to: .failed(failure), keepToken: true)
    }

    /// Token-gated reconnect completion. Only the CURRENT failed run may retry.
    /// Late reconnects after stop/background/newer starts have no effect.
    @discardableResult
    public func retry(after token: SharingSessionToken) -> SharingSessionToken? {
        guard currentToken == token, case .failed = state else { return nil }
        // The background guard is already established by the state check above.
        return try? start()
    }

    private func invalidate(to newState: SharingSessionState, keepToken: Bool) {
        state = newState
        if !keepToken { currentToken = nil }
        pending = nil
        lastAccepted = nil
        wakeup?.isFinished = true
        // Set cancellation flags BEFORE calling external code: cancellation may
        // synchronously deliver completion and reenter this object.
        var sendCancellation: (any SharingCancellation)?
        if flight != nil, flight?.cancellationRequested == false {
            flight?.cancellationRequested = true
            sendCancellation = flight?.cancellation
        }
        pump()
        sendCancellation?.cancel()
    }

    private func clockReading() -> TimeInterval? {
        let now = scheduler.now
        guard now.isFinite, now >= 0,
              lastClockReading.map({ now >= $0 }) ?? true else { return nil }
        lastClockReading = now
        return now
    }

    private func pump() {
        pumpRequested = true
        guard !isPumping else { return }
        isPumping = true
        defer { isPumping = false }
        // Drain only requests made by synchronous callbacks/API reentrancy. This
        // is not time polling: no request means no next iteration. Coalescing
        // prevents an external registration/cancellation call stack per restart.
        while pumpRequested {
            pumpRequested = false
            pumpOnce()
        }
    }

    private func pumpOnce() {
        if let wakeup, wakeup.isFinished {
            // Reentrant stop/start/submit may update current state while cancel()
            // runs, but cannot enter another pumpOnce or free this reservation.
            wakeup.cancellation?.cancel()
            self.wakeup = nil
        }
        guard state == .running, let token = currentToken, pending != nil,
              flight == nil, wakeup == nil else { return }
        guard let now = clockReading() else {
            invalidate(to: .failed(.invalidClock), keepToken: true)
            return
        }
        if now < nextSendAt {
            let id = UUID()
            let deadline = nextSendAt
            wakeup = Wakeup(id: id)
            let cancellation = scheduler.schedule(at: deadline) { [weak self] in
                self?.didWake(id: id, token: token, deadline: deadline)
            }
            // Reentrant callbacks can finish this wakeup, but the outer drain
            // retains its reservation until this handle is acquired and cleaned.
            wakeup?.cancellation = cancellation
            if wakeup?.isFinished == true { pumpRequested = true }
            return
        }
        let next = now + interval
        // Require progress even when a large floating-point clock cannot represent
        // this interval; otherwise an immediate sink could bypass pacing.
        guard next.isFinite, next > now else {
            invalidate(to: .failed(.invalidClock), keepToken: true)
            return
        }
        guard let frame = pending else { return }
        pending = nil
        nextSendAt = next
        let id = UUID()
        flight = Flight(id: id)
        let cancellation = transport.send(frame) { [weak self] result in
            self?.didComplete(id: id, token: token, result: result)
        }
        if flight?.id == id {
            flight?.cancellation = cancellation
            if flight?.cancellationRequested == true { cancellation.cancel() }
        }
    }

    private func didWake(id: UUID, token: SharingSessionToken, deadline: TimeInterval) {
        guard wakeup?.id == id, wakeup?.isFinished == false,
              currentToken == token, state == .running else { return }
        wakeup?.isFinished = true
        guard let now = clockReading(), now >= deadline else {
            invalidate(to: .failed(.invalidClock), keepToken: true)
            return
        }
        pump()
    }

    private func didComplete(
        id: UUID,
        token: SharingSessionToken,
        result: Result<Void, SharingFailure>
    ) {
        guard flight?.id == id else { return } // Also ignores duplicate completions.
        flight = nil
        if currentToken == token, state == .running, case .failure(let failure) = result {
            invalidate(to: .failed(failure), keepToken: true)
            return
        }
        // A stale result only releases its old resource reservation. Its success or
        // failure cannot change the new run's state/order or resurrect a stopped run.
        // Any CURRENT pending work can now proceed, respecting global pacing.
        pump()
    }
}
