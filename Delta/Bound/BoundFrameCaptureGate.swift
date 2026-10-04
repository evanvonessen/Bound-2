import Foundation

/// One capture/conversion in flight, at most 30 per second, with epoch fencing.
/// All state shared with Delta's owner callback is protected by this lock.
final class BoundFrameCaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var pending = false
    private var nextTime: TimeInterval = 0
    private var epoch: UInt64 = 0
    func configure(enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled; epoch &+= 1; nextTime = 0
    }
    func begin(now: TimeInterval) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard enabled, !pending, now >= nextTime else { return nil }
        pending = true
        let interval = 1.0 / 30
        // Keep sampling phase across ordinary source jitter. Missed slots are
        // discarded after a stall; never enqueue catch-up conversions.
        if nextTime == 0 { nextTime = now + interval }
        else { nextTime += (floor((now - nextTime) / interval) + 1) * interval }
        return epoch
    }
    func finish(epoch: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        pending = false
        return enabled && self.epoch == epoch
    }
}
