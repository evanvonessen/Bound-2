import UIKit
import DeltaCore

/// Companion UI only: this button never enters Delta's emulator input mapping.
@MainActor
final class BoundCompanionCycleButton: UIButton {
    var cycle: (() -> Void)?
    private var visualSize = CGSize(width: 17, height: 17)
    private var landscape = false
    private var minimal = false
    private var content: BoundPiPContent = .friend
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "bound.panel-cycle"
        accessibilityLabel = "Bound companion panel"
        accessibilityHint = "Cycles Friend, Notes, and Types"
        addTarget(self, action: #selector(advance), for: .touchUpInside)
        backgroundColor = .clear
        isExclusiveTouch = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func advance() { cycle?() }
    func configure(menuFrame: CGRect, controllerFrame: CGRect, landscape: Bool, minimal: Bool,
                   content: BoundPiPContent, canvas: CGRect, occupied: [CGRect], rightShoulderFrame: CGRect? = nil, menuHitSize: CGSize? = nil) {
        self.landscape = landscape; self.minimal = minimal; self.content = content
        visualSize = minimal ? CGSize(width: max(48, menuFrame.width), height: max(44, menuFrame.height)) : menuFrame.size
        let hitSize = CGSize(width: max(44, max(visualSize.width, menuHitSize?.width ?? 0)), height: max(44, max(visualSize.height, menuHitSize?.height ?? 0)))
        let preferred: CGPoint
        if !landscape {
            preferred = CGPoint(x: controllerFrame.minX + controllerFrame.maxX - menuFrame.midX, y: menuFrame.midY)
        } else if let right = rightShoulderFrame {
            preferred = CGPoint(x: right.midX, y: right.maxY + hitSize.height / 2 + 10)
        } else {
            preferred = CGPoint(x: controllerFrame.minX + controllerFrame.maxX - menuFrame.midX, y: menuFrame.midY)
        }
        guard let available = Self.clearFrame(preferred: preferred, size: hitSize, canvas: canvas, occupied: occupied) else {
            // A pathological custom layout can fill the entire viewport. Do not
            // put a companion hit target over native game inputs in that case.
            isHidden = true; isUserInteractionEnabled = false; frame = .zero
            return
        }
        isHidden = false; isUserInteractionEnabled = true; frame = available
        accessibilityValue = content.rawValue.capitalized
        setNeedsDisplay()
    }
    /// Nearest collision-free center among viewport and native-hit-region edges.
    /// The ordinary mirrored/adjacent placement exits immediately without a search.
    static func clearFrame(preferred: CGPoint, size: CGSize, canvas: CGRect, occupied: [CGRect]) -> CGRect? {
        guard size.width > 0, size.height > 0, canvas.width >= size.width, canvas.height >= size.height else { return nil }
        let halfW = size.width / 2, halfH = size.height / 2
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, canvas.minX + halfW), canvas.maxX - halfW),
                    y: min(max(point.y, canvas.minY + halfH), canvas.maxY - halfH))
        }
        func frame(_ point: CGPoint) -> CGRect {
            CGRect(x: point.x - halfW, y: point.y - halfH, width: size.width, height: size.height)
        }
        func clear(_ rect: CGRect) -> Bool {
            canvas.contains(rect) && !occupied.contains { $0.intersects(rect) }
        }
        let initial = clamp(preferred), first = frame(initial)
        if clear(first) { return first }
        var xs = [initial.x, canvas.minX + halfW, canvas.maxX - halfW]
        var ys = [initial.y, canvas.minY + halfH, canvas.maxY - halfH]
        for obstacle in occupied where !obstacle.isNull && !obstacle.isEmpty {
            xs += [obstacle.minX - halfW - 2, obstacle.maxX + halfW + 2]
            ys += [obstacle.minY - halfH - 2, obstacle.maxY + halfH + 2]
        }
        let candidates = xs.flatMap { x in ys.map { y in clamp(CGPoint(x: x, y: y)) } }.sorted {
            let ax = $0.x - initial.x, ay = $0.y - initial.y
            let bx = $1.x - initial.x, by = $1.y - initial.y
            let a = ax * ax + ay * ay
            let b = bx * bx + by * by
            if a == b { return $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
            return a < b
        }
        for candidate in candidates { let rect = frame(candidate); if clear(rect) { return rect } }
        return nil
    }
    override func draw(_ rect: CGRect) {
        let box = CGRect(x: bounds.midX-visualSize.width/2, y: bounds.midY-visualSize.height/2, width: visualSize.width, height: visualSize.height)
        let fill: UIColor = minimal ? .secondarySystemBackground : landscape ? .deltaPurple : .black
        let ink: UIColor = minimal ? .label : .white
        let shape = UIBezierPath(roundedRect: box, cornerRadius: min(box.width, box.height)/2)
        fill.setFill(); shape.fill()
        if landscape || minimal { UIColor.white.withAlphaComponent(minimal ? 0.25 : 0.85).setStroke(); shape.lineWidth = 1.5; shape.stroke() }
        if let mark = UIImage(named: "DeltaBoundMark")?.withTintColor(ink, renderingMode: .alwaysOriginal) {
            let side = min(box.width, box.height) * 0.72
            mark.draw(in: CGRect(x: box.midX-side/2, y: box.midY-side/2, width: side, height: side))
        }
    }
}

/// Describes the real Menu hit region; ordinary taps still reach Delta's native touch view.
@MainActor
final class BoundNativeMenuAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}
