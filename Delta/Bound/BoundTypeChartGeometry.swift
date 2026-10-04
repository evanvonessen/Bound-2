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
        initialScale = scale
        minimumScale = min(viewport.width / image.width, scale)
        maximumScale = scale * 8
    }
    static func portraitViewport(bounds: CGRect, gameFrame: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
               height: max(0, min(bounds.maxY, gameFrame.minY) - bounds.minY))
    }
    static func centeredInsets(content: CGSize, viewport: CGSize) -> (horizontal: CGFloat, vertical: CGFloat) {
        (max(0, (viewport.width - content.width) / 2), max(0, (viewport.height - content.height) / 2))
    }
}
