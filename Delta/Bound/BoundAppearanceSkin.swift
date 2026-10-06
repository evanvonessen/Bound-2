import UIKit
import DeltaCore

/// Keeps native centers, item IDs and inputs. Minimal expands small touch regions
/// to 44 points and draws readable capsules without changing saved placements.
final class BoundMinimalControllerSkin: ControllerSkinProtocol {
    let base: ControllerSkinProtocol
    let canvasSize: CGSize
    let appearance: UITraitCollection
    init(base: ControllerSkinProtocol, canvasSize: CGSize, traits: UITraitCollection) {
        self.base = base; self.canvasSize = canvasSize; self.appearance = traits
    }
    var name: String { "Minimal" }
    var identifier: String { base.identifier + ".bound-minimal." + String(describing: canvasSize) + "." + String(appearance.userInterfaceStyle.rawValue) + "." + String(appearance.accessibilityContrast.rawValue) }
    var gameType: GameType { base.gameType }
    var isDebugModeEnabled: Bool { base.isDebugModeEnabled }
    func supports(_ traits: DeltaCore.ControllerSkin.Traits) -> Bool { base.supports(traits) }
    func supportedTraits(for traits: DeltaCore.ControllerSkin.Traits) -> DeltaCore.ControllerSkin.Traits? { base.supportedTraits(for: traits) }
    func items(for traits: DeltaCore.ControllerSkin.Traits) -> [DeltaCore.ControllerSkin.Item]? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return base.items(for: traits) }
        return base.items(for: traits)?.map { item in
            guard item.kind == .button else { return item }
            var result = item
            let center = CGPoint(x: item.frame.midX, y: item.frame.midY)
            let label = Self.label(for: item)
            if label == "MENU", abs(item.frame.width*canvasSize.width-44) < 0.5, abs(item.frame.height*canvasSize.height-44) < 0.5 { return item }
            let width: CGFloat = label.count > 1 ? max(44, CGFloat(label.count) * 8 + 16) : 44
            let target = CGRect(x: center.x - width / 2 / canvasSize.width,
                                y: center.y - 22 / canvasSize.height,
                                width: width / canvasSize.width, height: 44 / canvasSize.height)
            result.extendedFrame = item.extendedFrame.union(target)
            return result
        }
    }
    func image(for traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> UIImage? { artwork(traits, pressed: false) }
    func pressedImage(for traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> UIImage? { artwork(traits, pressed: true) }
    func image(for item: DeltaCore.ControllerSkin.Item, traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> (UIImage, CGSize)? {
        // Native individual button assets would cover our composite. Thumbsticks retain
        // their native moving assets and input behavior.
        item.kind == .thumbstick ? base.image(for: item, traits: traits, preferredSize: preferredSize) : nil
    }
    private func artwork(_ traits: DeltaCore.ControllerSkin.Traits, pressed: Bool) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0, let items = base.items(for: traits) else { return nil }
        return UIGraphicsImageRenderer(size: canvasSize).image { context in
            let fill = (pressed ? UIColor.systemGray2 : UIColor.secondarySystemBackground).resolvedColor(with: appearance)
            let ink = UIColor.label.resolvedColor(with: appearance)
            if let stock = base as? BoundStockControllerSkin {
                stock.drawPortraitWordmark(in: context.cgContext, size: canvasSize, traits: traits, color: .white)
            }
            for item in items where item.kind == .button || item.kind == .dPad {
                let nativeFrame = item.frame.applying(.init(scaleX: canvasSize.width, y: canvasSize.height))
                guard nativeFrame.width > 0, nativeFrame.height > 0 else { continue }
                let label = Self.label(for: item)
                let compactMenu = label == "MENU" && abs(nativeFrame.width-44) < 0.5 && abs(nativeFrame.height-44) < 0.5
                let minWidth: CGFloat = compactMenu ? 44 : label.count > 1 ? max(44, CGFloat(label.count) * 8 + 16) : 44
                let drawingSize = item.kind == .button ? CGSize(width: max(nativeFrame.width, minWidth), height: max(nativeFrame.height, 44)) : nativeFrame.size
                let frame = CGRect(x: nativeFrame.midX - drawingSize.width/2, y: nativeFrame.midY - drawingSize.height/2, width: drawingSize.width, height: drawingSize.height).insetBy(dx: 1, dy: 1)
                let path: UIBezierPath
                if item.kind == .dPad {
                    let x = frame.minX, y = frame.minY, w = frame.width, h = frame.height
                    path = UIBezierPath()
                    path.move(to: CGPoint(x: x+w/3, y: y)); path.addLine(to: CGPoint(x: x+2*w/3, y: y))
                    path.addLine(to: CGPoint(x: x+2*w/3, y: y+h/3)); path.addLine(to: CGPoint(x: x+w, y: y+h/3))
                    path.addLine(to: CGPoint(x: x+w, y: y+2*h/3)); path.addLine(to: CGPoint(x: x+2*w/3, y: y+2*h/3))
                    path.addLine(to: CGPoint(x: x+2*w/3, y: y+h)); path.addLine(to: CGPoint(x: x+w/3, y: y+h))
                    path.addLine(to: CGPoint(x: x+w/3, y: y+2*h/3)); path.addLine(to: CGPoint(x: x, y: y+2*h/3))
                    path.addLine(to: CGPoint(x: x, y: y+h/3)); path.addLine(to: CGPoint(x: x+w/3, y: y+h/3)); path.close()
                } else { path = UIBezierPath(roundedRect: frame, cornerRadius: min(frame.width, frame.height)/2) }
                fill.setFill(); path.fill(); ink.withAlphaComponent(0.65).setStroke(); path.lineWidth = appearance.accessibilityContrast == .high ? 2 : 1; path.stroke()
                if item.kind == .button {
                    let font = UIFont.systemFont(ofSize: min(17, max(12, min(frame.height * 0.32, frame.width / CGFloat(max(1, label.count)) * 1.4))), weight: .semibold)
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
                    let size = (label as NSString).size(withAttributes: attributes)
                    context.cgContext.saveGState(); context.cgContext.clip(to: frame)
                    (label as NSString).draw(at: CGPoint(x: frame.midX-size.width/2, y: frame.midY-size.height/2), withAttributes: attributes)
                    context.cgContext.restoreGState()
                }
            }
        }
    }
    private static func label(for item: DeltaCore.ControllerSkin.Item) -> String {
        item.inputs.allInputs.map { input in
            switch input.stringValue.lowercased() {
            case "fastforward": return "FF"
            case "quicksave": return "Save"
            case "quickload": return "Load"
            default: return input.stringValue.uppercased()
            }
        }.joined(separator: "/")
    }
    func isTranslucent(for traits: DeltaCore.ControllerSkin.Traits) -> Bool? { base.isTranslucent(for: traits) }
    func gameScreenFrame(for traits: DeltaCore.ControllerSkin.Traits) -> CGRect? { base.gameScreenFrame(for: traits) }
    func screens(for traits: DeltaCore.ControllerSkin.Traits) -> [DeltaCore.ControllerSkin.Screen]? { base.screens(for: traits) }
    func aspectRatio(for traits: DeltaCore.ControllerSkin.Traits) -> CGSize? { base.aspectRatio(for: traits) }
    func contentSize(for traits: DeltaCore.ControllerSkin.Traits) -> CGSize? { base.contentSize(for: traits) }
    func menuInsets(for traits: DeltaCore.ControllerSkin.Traits) -> UIEdgeInsets? { base.menuInsets(for: traits) }
}
