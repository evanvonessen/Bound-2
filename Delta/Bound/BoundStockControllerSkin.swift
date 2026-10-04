import UIKit
import DeltaCore

/// App-owned artwork/stock placement policy. Upstream skin files and native inputs stay intact.
final class BoundStockControllerSkin: ControllerSkinProtocol {
    let base: ControllerSkinProtocol
    let canvasSize: CGSize
    let contentInsets: UIEdgeInsets
    init(base: ControllerSkinProtocol, canvasSize: CGSize, contentInsets: UIEdgeInsets = .zero) {
        self.base = base; self.canvasSize = canvasSize; self.contentInsets = contentInsets
    }
    private var stock: Bool { ["gba", "gbc", "nes", "snes", "n64", "genesis", "ds"].contains { base.identifier == "com.delta." + $0 + ".standard" } }
    var name: String { base.name }
    var identifier: String { base.identifier + ".bound-stock.v2." + String(describing: canvasSize) + String(describing: contentInsets) }
    var gameType: GameType { base.gameType }
    var isDebugModeEnabled: Bool { base.isDebugModeEnabled }
    func supports(_ traits: DeltaCore.ControllerSkin.Traits) -> Bool { base.supports(traits) }
    func supportedTraits(for traits: DeltaCore.ControllerSkin.Traits) -> DeltaCore.ControllerSkin.Traits? { base.supportedTraits(for: traits) }
    func items(for traits: DeltaCore.ControllerSkin.Traits) -> [DeltaCore.ControllerSkin.Item]? {
        guard let original = base.items(for: traits), stock, traits.orientation == .landscape,
              ["com.delta.gba.standard", "com.delta.snes.standard", "com.delta.n64.standard"].contains(base.identifier),
              let left = original.first(where: { Self.hasInput("l", $0) }), canvasSize.height > 0, canvasSize.width > 0 else { return base.items(for: traits) }
        return original.map { item in
            guard Self.hasInput("menu", item) else { return item }
            var result = item
            let topMargin = item.frame.minY - item.extendedFrame.minY
            let target = CGPoint(x: left.frame.midX, y: left.extendedFrame.maxY + topMargin + 10 / canvasSize.height)
            let dx = target.x - item.frame.midX, dy = target.y - item.frame.minY
            result.frame = item.frame.offsetBy(dx: dx, dy: dy)
            result.extendedFrame = item.extendedFrame.offsetBy(dx: dx, dy: dy)
            // Clamp the complete native touch target, not just its visible artwork.
            // This moves the stock default inward around landscape notches while
            // retaining its native size and the shoulder-to-menu vertical gap.
            let safe = CGRect(origin: .zero, size: canvasSize).inset(by: contentInsets)
                .applying(.init(scaleX: 1 / canvasSize.width, y: 1 / canvasSize.height))
            let hit = result.extendedFrame
            let shiftX = safe.width >= hit.width ? min(max(hit.minX, safe.minX), safe.maxX-hit.width)-hit.minX : safe.midX-hit.midX
            let shiftY = safe.height >= hit.height ? min(max(hit.minY, safe.minY), safe.maxY-hit.height)-hit.minY : safe.midY-hit.midY
            result.frame = result.frame.offsetBy(dx: shiftX, dy: shiftY)
            result.extendedFrame = result.extendedFrame.offsetBy(dx: shiftX, dy: shiftY)
            return result
        }
    }
    private static func hasInput(_ name: String, _ item: DeltaCore.ControllerSkin.Item) -> Bool { item.inputs.allInputs.contains { $0.stringValue == name } }
    private func artwork(_ image: UIImage?, traits: DeltaCore.ControllerSkin.Traits) -> UIImage? {
        guard stock, let image else { return image }
        let sourceItems = base.items(for: traits) ?? [], targetItems = items(for: traits) ?? []
        let size = image.size
        func scaled(_ normalized: CGRect) -> CGRect { normalized.applying(.init(scaleX: size.width, y: size.height)) }
        return UIGraphicsImageRenderer(size: size).image { context in
            image.draw(at: .zero)
            if traits.orientation == .landscape,
               let menu = sourceItems.first(where: { Self.hasInput("menu", $0) }),
               let moved = targetItems.first(where: { $0.id == menu.id }), moved.frame != menu.frame {
                let old = scaled(menu.frame), destination = scaled(moved.frame)
                context.cgContext.saveGState(); context.cgContext.setBlendMode(.clear)
                context.cgContext.fill(old.insetBy(dx: -2, dy: -2)); context.cgContext.restoreGState()
                context.cgContext.saveGState(); context.cgContext.clip(to: destination)
                image.draw(at: CGPoint(x: destination.minX-old.minX, y: destination.minY-old.minY))
                context.cgContext.restoreGState()
            }
            if traits.orientation == .portrait && traits.device == .iphone {
                let core = base.identifier.replacingOccurrences(of: "com.delta.", with: "").replacingOccurrences(of: ".standard", with: "")
                let edge = traits.displayType == .edgeToEdge
                // Measured official PDF motif regions. Sample neighboring plain casing
                // pixels to preserve each skin's actual color/gradient, not a guessed fill.
                let top: CGRect?
                switch core {
                case "gba", "snes": top = CGRect(x: 0.40, y: 0, width: 0.20, height: edge ? 0.055 : 0.065)
                case "gbc": top = CGRect(x: 0.40, y: 0.025, width: 0.20, height: edge ? 0.055 : 0.065)
                case "n64": top = CGRect(x: 0.40, y: 0, width: 0.20, height: 0.045)
                case "nes": top = CGRect(x: 0.04, y: edge ? 0.045 : 0.03, width: 0.19, height: 0.065)
                default: top = nil
                }
                if let top {
                    let rect = scaled(top)
                    context.cgContext.saveGState(); context.cgContext.clip(to: rect)
                    image.draw(at: CGPoint(x: 0, y: -rect.height - 5))
                    context.cgContext.restoreGState()
                }
                let bottom: CGRect?
                switch core {
                case "gba": bottom = CGRect(x: 0.89, y: edge ? 0.77 : 0.85, width: 0.09, height: edge ? 0.115 : 0.13)
                case "gbc", "snes": bottom = CGRect(x: 0.89, y: edge ? 0.77 : 0.87, width: 0.09, height: edge ? 0.10 : 0.11)
                case "n64": bottom = CGRect(x: 0.89, y: edge ? 0.82 : 0.91, width: 0.09, height: edge ? 0.075 : 0.07)
                case "genesis": bottom = CGRect(x: 0.88, y: edge ? 0.77 : 0.83, width: 0.10, height: edge ? 0.115 : 0.125)
                case "ds": bottom = CGRect(x: edge ? 0.71 : 0.73, y: edge ? 0.805 : 0.82, width: edge ? 0.08 : 0.09, height: edge ? 0.035 : 0.05)
                default: bottom = nil
                }
                if let bottom {
                    let rect = scaled(bottom)
                    context.cgContext.saveGState(); context.cgContext.clip(to: rect)
                    image.draw(at: CGPoint(x: rect.width + 5, y: 0))
                    context.cgContext.restoreGState()
                    // GBA's interactive companion mark occupies the removed logo spot.
                    // Other console motifs use the composite branding in their own slot.
                    if core != "gba", let mark = UIImage(named: "DeltaBoundMark") {
                        let side = min(rect.width, rect.height)
                        mark.draw(in: CGRect(x: rect.midX-side/2, y: rect.midY-side/2, width: side, height: side))
                    }
                }
            }
        }
    }
    func image(for traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> UIImage? { artwork(base.image(for: traits, preferredSize: preferredSize), traits: traits) }
    func pressedImage(for traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> UIImage? { artwork(base.pressedImage(for: traits, preferredSize: preferredSize), traits: traits) }
    func image(for item: DeltaCore.ControllerSkin.Item, traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> (UIImage, CGSize)? { base.image(for: item, traits: traits, preferredSize: preferredSize) }
    func isTranslucent(for traits: DeltaCore.ControllerSkin.Traits) -> Bool? { base.isTranslucent(for: traits) }
    func gameScreenFrame(for traits: DeltaCore.ControllerSkin.Traits) -> CGRect? { base.gameScreenFrame(for: traits) }
    func screens(for traits: DeltaCore.ControllerSkin.Traits) -> [DeltaCore.ControllerSkin.Screen]? { base.screens(for: traits) }
    func aspectRatio(for traits: DeltaCore.ControllerSkin.Traits) -> CGSize? { base.aspectRatio(for: traits) }
    func contentSize(for traits: DeltaCore.ControllerSkin.Traits) -> CGSize? { base.contentSize(for: traits) }
    func menuInsets(for traits: DeltaCore.ControllerSkin.Traits) -> UIEdgeInsets? { base.menuInsets(for: traits) }
}
