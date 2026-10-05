import UIKit

/// Attach to the gameplay ancestor for old Bound's canvas-wide gestures.
/// The owner filters native controls, chrome and text editors before recognition.
@MainActor
final class BoundPiPGestures: NSObject, UIGestureRecognizerDelegate {
    private weak var view: UIView?
    private let shouldReceive: (UITouch) -> Bool
    private let moved: (UIGestureRecognizer.State, CGSize, CGFloat) -> Void
    private let magnified: (UIGestureRecognizer.State, CGFloat) -> Void
    private let opacityChanged: (UIGestureRecognizer.State, CGFloat) -> Void
    private let allowsOpacity: () -> Bool
    private let isCenteredTouch: (UITouch) -> Bool
    private let isPiPTouch: (UITouch) -> Bool
    private var recognizers: [UIGestureRecognizer] = []
    private var moveTouchGate = BoundPiPTouchCountGate()
    private var pinchTouchGate = BoundPiPTouchCountGate()
    private var centerTouchGate = BoundPiPTouchCountGate()
    private weak var centerFade: UIPanGestureRecognizer?
    private var lastMove = CGSize.zero
    private var lastEndX: CGFloat = 0
    private var lastScale: CGFloat = 1
    private var lastCenterTranslation: CGFloat = 0

    init(view: UIView, shouldReceive: @escaping (UITouch) -> Bool,
         moved: @escaping (UIGestureRecognizer.State, CGSize, CGFloat) -> Void,
         magnified: @escaping (UIGestureRecognizer.State, CGFloat) -> Void,
         opacityChanged: @escaping (UIGestureRecognizer.State, CGFloat) -> Void,
         allowsOpacity: @escaping () -> Bool = { true },
         isCenteredTouch: @escaping (UITouch) -> Bool = { _ in false },
         isPiPTouch: @escaping (UITouch) -> Bool = { _ in true }) {
        self.view = view; self.shouldReceive = shouldReceive
        self.moved = moved; self.magnified = magnified; self.opacityChanged = opacityChanged
        self.allowsOpacity = allowsOpacity; self.isCenteredTouch = isCenteredTouch
        self.isPiPTouch = isPiPTouch
        super.init()
        let pan = BoundPiPReleasePan(target: self, action: #selector(move(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        let pinch = BoundPiPReleasePinch(target: self, action: #selector(pinch(_:)))
        let center = BoundPiPReleasePan(target: self, action: #selector(centerOpacity(_:)))
        center.minimumNumberOfTouches = 2; center.maximumNumberOfTouches = 2
        centerFade = center
        recognizers = [pan, pinch, center]
        for recognizer in recognizers {
            recognizer.cancelsTouchesInView = true
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
    }
    func setEnabled(_ enabled: Bool) {
        for recognizer in recognizers { recognizer.isEnabled = enabled }
    }
    func cancel() {
        for recognizer in recognizers where recognizer.isEnabled {
            recognizer.isEnabled = false; recognizer.isEnabled = true
        }
    }
    func detach() {
        for recognizer in recognizers { view?.removeGestureRecognizer(recognizer) }
        recognizers.removeAll(); view = nil
    }
    @objc private func move(_ gesture: UIPanGestureRecognizer) {
        let releasing = (gesture as? BoundPiPReleasePan)?.isReleasing ?? false
        switch moveTouchGate.update(phase: gesture.state, touches: gesture.numberOfTouches, required: 1, releasing: releasing) {
        case .cancel: moved(.cancelled, .zero, gesture.location(in: view).x)
        case .ignore: break
        case .deliver:
            if gesture.state == .began || (gesture.state == .changed && !releasing) {
                let movement = gesture.translation(in: view)
                lastMove = CGSize(width: movement.x, height: movement.y); lastEndX = gesture.location(in: view).x
            }
            moved(gesture.state, lastMove, lastEndX)
        }
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        let releasing = (gesture as? BoundPiPReleasePinch)?.isReleasing ?? false
        switch pinchTouchGate.update(phase: gesture.state, touches: gesture.numberOfTouches, required: 2, releasing: releasing) {
        case .cancel: magnified(.cancelled, 1)
        case .ignore: break
        case .deliver:
            if gesture.state == .began || (gesture.state == .changed && !releasing) { lastScale = gesture.scale }
            magnified(gesture.state, lastScale)
        }
    }
    @objc private func centerOpacity(_ gesture: UIPanGestureRecognizer) {
        deliverOpacity(gesture, gate: &centerTouchGate, translation: &lastCenterTranslation, required: 2)
    }
    private func deliverOpacity(_ gesture: UIPanGestureRecognizer, gate: inout BoundPiPTouchCountGate,
                                translation: inout CGFloat, required: Int) {
        let releasing = (gesture as? BoundPiPReleasePan)?.isReleasing ?? false
        switch gate.update(phase: gesture.state, touches: gesture.numberOfTouches, required: required, releasing: releasing) {
        case .cancel: opacityChanged(.cancelled, 0)
        case .ignore: break
        case .deliver:
            if gesture.state == .began || (gesture.state == .changed && !releasing) { translation = gesture.translation(in: view).y }
            opacityChanged(gesture.state, translation)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard shouldReceive(touch) else { return false }
        if gestureRecognizer === centerFade { return allowsOpacity() && isCenteredTouch(touch) }
        return isPiPTouch(touch)
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pinch = gestureRecognizer as? UIPinchGestureRecognizer { return pinch.numberOfTouches == 2 }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.minimumNumberOfTouches >= 2 else { return true }
        guard allowsOpacity() else { return false }
        let movement = pan.translation(in: view)
        return abs(movement.y) > abs(movement.x) * 1.5
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === centerFade || otherGestureRecognizer === centerFade { return false }
        return recognizers.contains(gestureRecognizer) && recognizers.contains(otherGestureRecognizer)
    }
}

/// Lifting fingers is completion, not an added-finger mode change. UIKit can emit
/// a changed callback with fewer touches before ended; retain the last full-hand preview.
private final class BoundPiPReleasePan: UIPanGestureRecognizer {
    private(set) var isReleasing = false
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if isReleasing && (state == .began || state == .changed) { state = .cancelled; return }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        isReleasing = true
        super.touchesEnded(touches, with: event)
    }
    override func reset() { super.reset(); isReleasing = false }
}
private final class BoundPiPReleasePinch: UIPinchGestureRecognizer {
    private(set) var isReleasing = false
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if isReleasing && (state == .began || state == .changed) { state = .cancelled; return }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        isReleasing = true
        super.touchesEnded(touches, with: event)
    }
    override func reset() { super.reset(); isReleasing = false }
}

/// UIKit touch-count limits govern recognition; they do not safely fence a gesture
/// that changes fingers after recognition. Once mismatched, require a fresh gesture.
struct BoundPiPTouchCountGate {
    enum Decision: Equatable { case deliver, cancel, ignore }
    private var suppressed = false
    mutating func update(phase: UIGestureRecognizer.State, touches: Int, required: Int, releasing: Bool = false) -> Decision {
        if phase == .began { suppressed = false }
        if phase == .changed, releasing, touches < required { return .ignore }
        if phase == .began || phase == .changed, touches != required {
            guard !suppressed else { return .ignore }
            suppressed = true; return .cancel
        }
        return suppressed ? .ignore : .deliver
    }
}
