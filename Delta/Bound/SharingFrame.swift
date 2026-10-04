import Foundation

public enum SharingPixelFormat: Sendable {
    case rgba8
    case bgra8
}

public enum SharingFrameError: Error, Equatable, Sendable {
    case invalidDimensions
    case unsupportedPixelFormat
    case invalidByteCount
    case invalidSequence
    case invalidCaptureTime
}

/// Detached game pixels. The initializer always copies, even if Data wraps mutable
/// external storage. Mutating an array returned by `rgba8` cannot change this frame.
public struct SharingFrame: Sendable, Equatable {
    public static let width = 240
    public static let height = 160
    public static let bytesPerRow = width * 4
    public static let byteCount = bytesPerRow * height

    public let rgba8: [UInt8]
    public let sequence: UInt64
    /// Elapsed seconds from an in-app stream event chosen by the producer.
    /// Never pass raw system uptime or wall-clock time to an off-device transport.
    public let capturedAt: TimeInterval

    public init(
        copying pixels: Data,
        width: Int = SharingFrame.width,
        height: Int = SharingFrame.height,
        pixelFormat: SharingPixelFormat = .rgba8,
        sequence: UInt64,
        capturedAt: TimeInterval
    ) throws {
        guard width == Self.width, height == Self.height else {
            throw SharingFrameError.invalidDimensions
        }
        guard pixelFormat == .rgba8 else {
            throw SharingFrameError.unsupportedPixelFormat
        }
        guard pixels.count == Self.byteCount else {
            throw SharingFrameError.invalidByteCount
        }
        guard sequence > 0 else { throw SharingFrameError.invalidSequence }
        guard capturedAt.isFinite, capturedAt >= 0 else {
            throw SharingFrameError.invalidCaptureTime
        }
        // Data's ordinary value copy may still share a bytesNoCopy allocation.
        // Array(UnsafeRawBufferPointer) allocates independent byte storage.
        self.rgba8 = pixels.withUnsafeBytes { Array($0) }
        self.sequence = sequence
        self.capturedAt = capturedAt
    }
}
