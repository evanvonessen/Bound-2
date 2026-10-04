import Foundation
import CoreGraphics

// Original Bound's PiP interaction policy; storage is isolated from its account preferences.
enum BoundPiPCorner: String, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}
enum BoundPiPContent: String, CaseIterable, Sendable { case friend, types, notes }
enum BoundPiPHiddenSide: String, Sendable { case left, right }

@MainActor
final class BoundPiPPreferences {
    private let defaults: UserDefaults
    private let namespace: String
    init(defaults: UserDefaults = .standard, namespace: String = "bound.delta.pip.v1") {
        self.defaults = defaults; self.namespace = namespace
    }
    private func key(_ suffix: String) -> String { namespace + "." + suffix }
    var corner: BoundPiPCorner {
        get { BoundPiPCorner(rawValue: defaults.string(forKey: key("corner")) ?? "") ?? .topRight }
        set { defaults.set(newValue.rawValue, forKey: key("corner")) }
    }
    func scale(for content: BoundPiPContent) -> Double {
        validNumber(key(content.rawValue + ".scale"), range: 0.65...1.4)
    }
    func opacity(for content: BoundPiPContent) -> Double {
        validNumber(key(content.rawValue + ".opacity"), range: 0...1)
    }
    private func validNumber(_ name: String, range: ClosedRange<Double>) -> Double {
        guard let value = defaults.object(forKey: name) as? NSNumber,
              value.doubleValue.isFinite, range.contains(value.doubleValue) else { return 1 }
        return value.doubleValue
    }
    func setScale(_ value: Double, for content: BoundPiPContent) {
        guard value.isFinite else { return }
        defaults.set(min(1.4, max(0.65, value)), forKey: key(content.rawValue + ".scale"))
    }
    func setOpacity(_ value: Double, for content: BoundPiPContent) {
        guard value.isFinite else { return }
        defaults.set(min(1, max(0, value)), forKey: key(content.rawValue + ".opacity"))
    }
    func transparency(for content: BoundPiPContent) -> Double { 1 - opacity(for: content) }
    func setTransparency(_ value: Double, for content: BoundPiPContent) { setOpacity(1 - value, for: content) }
    static func opacity(start: Double, verticalTranslation: CGFloat, panelHeight: CGFloat) -> Double {
        guard start.isFinite, verticalTranslation.isFinite, panelHeight.isFinite else { return 1 }
        return min(1, max(0, start - Double(verticalTranslation / max(1, panelHeight))))
    }
}

struct BoundPiPLayout {
    let viewport: CGRect
    let size: CGSize
    private let padding: CGFloat = 8
    init(viewport: CGRect, baseSize: CGSize, scale: CGFloat) {
        self.viewport = viewport
        self.size = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
    }
    func center(_ corner: BoundPiPCorner) -> CGPoint {
        let left = viewport.minX + padding + size.width / 2
        let right = viewport.maxX - padding - size.width / 2
        let top = viewport.minY + padding + size.height / 2
        let bottom = viewport.maxY - padding - size.height / 2
        return CGPoint(x: corner == .topLeft || corner == .bottomLeft ? left : right,
                       y: corner == .topLeft || corner == .topRight ? top : bottom)
    }
    func clampedCenter(from corner: BoundPiPCorner, translation: CGSize) -> CGPoint {
        let origin = center(corner)
        let left = viewport.minX + padding + size.width / 2
        let right = viewport.maxX - padding - size.width / 2
        let top = viewport.minY + padding + size.height / 2
        let bottom = viewport.maxY - padding - size.height / 2
        return CGPoint(x: min(max(origin.x + translation.width, left), max(left, right)),
                       y: min(max(origin.y + translation.height, top), max(top, bottom)))
    }
    func destination(from corner: BoundPiPCorner, translation: CGSize) -> BoundPiPCorner {
        let thresholdX = min(70, viewport.width * 0.16)
        let thresholdY = min(55, viewport.height * 0.16)
        let left = translation.width < -thresholdX ? true : translation.width > thresholdX ? false
            : corner == .topLeft || corner == .bottomLeft
        let top = translation.height < -thresholdY ? true : translation.height > thresholdY ? false
            : corner == .topLeft || corner == .topRight
        switch (top, left) {
        case (true, true): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }
    func hiddenSide(from corner: BoundPiPCorner, translation: CGSize, endX: CGFloat? = nil) -> BoundPiPHiddenSide? {
        guard abs(translation.width) > 50 else { return nil }
        if let endX {
            if endX <= viewport.minX + 20 && translation.width < 0 { return .left }
            if endX >= viewport.maxX - 20 && translation.width > 0 { return .right }
        } else {
            let rawX = center(corner).x + translation.width
            if rawX <= viewport.minX + 12 && translation.width < 0 { return .left }
            if rawX >= viewport.maxX - 12 && translation.width > 0 { return .right }
        }
        return nil
    }
}
