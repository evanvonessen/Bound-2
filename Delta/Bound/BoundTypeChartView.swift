import SwiftUI
import UIKit

/// Portrait only. Landscape deliberately retains its existing content and outer PiP gestures.
struct BoundTypeChartView: UIViewRepresentable {
    func makeUIView(context: Context) -> BoundPortraitChartScrollView { BoundPortraitChartScrollView() }
    func updateUIView(_ uiView: BoundPortraitChartScrollView, context: Context) {}
}

final class BoundPortraitChartScrollView: UIScrollView, UIScrollViewDelegate {
    private let chart = UIImageView(image: UIImage(named: "PokemonTypeChart"))
    private var previousViewport = CGSize.zero
    private var initialScale: CGFloat = 1
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        accessibilityIdentifier = "bound.type-chart"
        accessibilityLabel = "Pokémon type effectiveness chart"
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        contentInsetAdjustmentBehavior = .never
        chart.contentMode = .scaleToFill // Bounds preserve the original image aspect ratio.
        chart.accessibilityIdentifier = "bound.type-chart-image"
        chart.accessibilityLabel = chart.image == nil ? "Type chart unavailable" : "Pokémon type effectiveness chart"
        chart.isAccessibilityElement = true
        chart.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in", target: self, selector: #selector(accessibleZoomIn)),
            UIAccessibilityCustomAction(name: "Zoom out", target: self, selector: #selector(accessibleZoomOut)),
            UIAccessibilityCustomAction(name: "Reset chart zoom", target: self, selector: #selector(accessibleReset))
        ]
        addSubview(chart)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousViewport, let image = chart.image,
              let geometry = BoundTypeChartGeometry(image: image.size, viewport: bounds.size) else { return }
        previousViewport = bounds.size
        // Layout/rotation and a newly created chart always start at the same height fit.
        minimumZoomScale = min(geometry.minimumScale, 1)
        maximumZoomScale = max(geometry.maximumScale, 1)
        setZoomScale(1, animated: false)
        chart.bounds = CGRect(origin: .zero, size: image.size)
        chart.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        initialScale = geometry.initialScale
        minimumZoomScale = geometry.minimumScale
        maximumZoomScale = geometry.maximumScale
        resetZoom()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { chart }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerSmallContent(); updateProbe() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateProbe() }
    private func centerSmallContent() {
        let padding = BoundTypeChartGeometry.centeredInsets(content: contentSize, viewport: bounds.size)
        contentInset = UIEdgeInsets(top: padding.vertical, left: padding.horizontal, bottom: padding.vertical, right: padding.horizontal)
    }
    private func resetZoom() {
        setZoomScale(initialScale, animated: false)
        centerSmallContent()
        setContentOffset(CGPoint(x: max(-contentInset.left, (contentSize.width - bounds.width)/2),
                                 y: max(-contentInset.top, (contentSize.height - bounds.height)/2)), animated: false)
        updateProbe()
    }
    private func updateProbe() {
        #if DEBUG
        let frame = chart.frame.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
        let value = String(format: "zoom=%.4f; initial=%.4f; imageX=%.2f; imageY=%.2f; imageWidth=%.2f; imageHeight=%.2f; viewportWidth=%.2f; viewportHeight=%.2f", Double(zoomScale), Double(initialScale), Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height), Double(bounds.width), Double(bounds.height))
        #else
        let value = String(format: "Zoom %.0f percent", Double(zoomScale / max(initialScale, 0.0001)) * 100)
        #endif
        accessibilityValue = value
        chart.accessibilityValue = value
    }
    @objc private func accessibleZoomIn() -> Bool { setZoomScale(min(maximumZoomScale, zoomScale * 1.5), animated: false); return true }
    @objc private func accessibleZoomOut() -> Bool { setZoomScale(max(minimumZoomScale, zoomScale / 1.5), animated: false); return true }
    @objc private func accessibleReset() -> Bool { resetZoom(); return true }
}
