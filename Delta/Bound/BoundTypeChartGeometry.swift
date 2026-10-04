import Foundation
import CoreGraphics

/// Portrait chart starts at height fit; zoom is session-local, never a PiP scale.
struct BoundTypeChartGeometry {
    let initialScale: CGFloat
    let minimumScale: CGFloat
    let maximumScale: CGFloat
    init?(image: CGSize, viewport: CGSize) {
        guard image.width.isFinite, image.height.isFinite, viewport.width.isFinite, viewport.height.isFinite,
              image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return nil }
        let scale = viewport.height / image.height
        guard scale.isFinite, scale > 0, (scale * 8).isFinite else { return nil }
        initialScale = scale; minimumScale = scale * 0.5; maximumScale = scale * 8
    }
    static func centeredInsets(content: CGSize, viewport: CGSize) -> (horizontal: CGFloat, vertical: CGFloat) {
        (max(0, (viewport.width - content.width) / 2), max(0, (viewport.height - content.height) / 2))
    }
}
