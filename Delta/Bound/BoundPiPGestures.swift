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
    private var recognizers: [UIGestureRecognizer] = []
    private var suppressCurrentPinch = false

    init(view: UIView, shouldReceive: @escaping (UITouch) -> Bool,
         moved: @escaping (UIGestureRecognizer.State, CGSize, CGFloat) -> Void,
         magnified: @escaping (UIGestureRecognizer.State, CGFloat) -> Void,
         opacityChanged: @escaping (UIGestureRecognizer.State, CGFloat) -> Void) {
        self.view = view; self.shouldReceive = shouldReceive
        self.moved = moved; self.magnified = magnified; self.opacityChanged = opacityChanged
        super.init()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(move(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let opacity = UIPanGestureRecognizer(target: self, action: #selector(opacity(_:)))
        opacity.minimumNumberOfTouches = 3; opacity.maximumNumberOfTouches = 3
        recognizers = [pan, pinch, opacity]
        for recognizer in recognizers {
            recognizer.cancelsTouchesInView = false
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
        let movement = gesture.translation(in: view)
        moved(gesture.state, CGSize(width: movement.x, height: movement.y), gesture.location(in: view).x)
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { suppressCurrentPinch = false }
        if gesture.state == .began || gesture.state == .changed {
            if gesture.numberOfTouches != 2 { suppressCurrentPinch = true; magnified(.cancelled, 1) }
        }
        guard !suppressCurrentPinch else { return }
        magnified(gesture.state, gesture.scale)
    }
    @objc private func opacity(_ gesture: UIPanGestureRecognizer) {
        opacityChanged(gesture.state, gesture.translation(in: view).y)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        shouldReceive(touch)
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pinch = gestureRecognizer as? UIPinchGestureRecognizer { return pinch.numberOfTouches == 2 }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.minimumNumberOfTouches == 3 else { return true }
        let movement = pan.translation(in: view)
        return abs(movement.y) >= abs(movement.x)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
