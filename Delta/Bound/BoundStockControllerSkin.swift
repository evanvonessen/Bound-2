import UIKit
import DeltaCore

/// App-owned artwork/stock placement policy. Upstream skin files and native inputs stay intact.
final class BoundStockControllerSkin: ControllerSkinProtocol {
    let base: ControllerSkinProtocol
    let canvasSize: CGSize
    let contentInsets: UIEdgeInsets
    /// Bound landscape only, expressed in the native controller's pixel coordinates.
    let boundLandscapeGutter: CGRect?
    init(base: ControllerSkinProtocol, canvasSize: CGSize, contentInsets: UIEdgeInsets = .zero, boundLandscapeGutter: CGRect? = nil) {
        self.base = base; self.canvasSize = canvasSize; self.contentInsets = contentInsets
        self.boundLandscapeGutter = boundLandscapeGutter
    }
    private var stock: Bool { ["gba", "gbc", "nes", "snes", "n64", "genesis", "ds"].contains { base.identifier == "com.delta." + $0 + ".standard" } }
    var name: String { base.name }
    var identifier: String { base.identifier + ".bound-stock.v2." + String(describing: canvasSize) + String(describing: contentInsets) + String(describing: boundLandscapeGutter) }
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
            if let gutter = boundLandscapeGutter,
               let right = original.first(where: { Self.hasInput("r", $0) }) {
                let toPixels = CGAffineTransform(scaleX: canvasSize.width, y: canvasSize.height)
                // Reserve Menu and the companion button together. Both remain
                // 44pt targets in the same slots when Controller Mode hides inputs.
                let slot = gutter.width >= 48 ? gutter.insetBy(dx: 2, dy: 0) : gutter
                let pairSize = CGSize(width: 44, height: 96)
                let obstacles = original.filter { !Self.hasInput("menu", $0) }.map { $0.extendedFrame.applying(toPixels) }
                let belowShoulder = right.extendedFrame.applying(toPixels).maxY + 10 + pairSize.height/2
                if let pair = Self.gutterFrame(preferredY: belowShoulder, size: pairSize, gutter: slot, occupied: obstacles) {
                    let frame = CGRect(x: pair.minX, y: pair.minY, width: 44, height: 44)
                    let normalized = CGAffineTransform(scaleX: 1/canvasSize.width, y: 1/canvasSize.height)
                    result.frame = frame.applying(normalized)
                    result.extendedFrame = result.frame
                    return result
                }
                // Unsupported/no-space layouts retain the usable native Menu.
            }
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
    /// Keep the gutter's outer edge and select the nearest clear vertical slot.
    static func gutterFrame(preferredY: CGFloat, size: CGSize, gutter: CGRect, occupied: [CGRect]) -> CGRect? {
        guard gutter.minX.isFinite, gutter.minY.isFinite, gutter.width.isFinite, gutter.height.isFinite,
              size.width.isFinite, size.height.isFinite, preferredY.isFinite,
              size.width >= 44, size.height >= 44, gutter.width >= size.width, gutter.height >= size.height else { return nil }
        let half = size.height/2
        func clampedY(_ y: CGFloat) -> CGFloat { min(max(y, gutter.minY+half), gutter.maxY-half) }
        let initial = clampedY(preferredY)
        var candidates = [initial, gutter.minY+half, gutter.maxY-half]
        for rect in occupied where !rect.isNull && !rect.isEmpty {
            candidates += [rect.minY-half-2, rect.maxY+half+2]
        }
        candidates = candidates.map(clampedY).sorted { abs($0-initial) < abs($1-initial) }
        for y in candidates {
            let frame = CGRect(x: gutter.maxX-size.width, y: y-half, width: size.width, height: size.height)
            if !occupied.contains(where: { frame.intersects($0) }) { return frame }
        }
        return nil
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
                if boundLandscapeGutter != nil, abs(moved.frame.width*canvasSize.width - 44) < 0.1,
                   abs(moved.frame.height*canvasSize.height - 44) < 0.1 {
                    drawMenu(in: destination)
                } else {
                    context.cgContext.saveGState(); context.cgContext.clip(to: destination)
                    let sx = destination.width/old.width, sy = destination.height/old.height
                    image.draw(in: CGRect(x: destination.minX-old.minX*sx, y: destination.minY-old.minY*sy,
                        width: size.width*sx, height: size.height*sy))
                    context.cgContext.restoreGState()
                }
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
    private func drawMenu(in frame: CGRect) {
        let box = frame.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: box, cornerRadius: box.height/2)
        UIColor.deltaPurple.setFill(); path.fill()
        UIColor.white.withAlphaComponent(0.85).setStroke(); path.lineWidth = 1.5; path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: box.height * 0.25, weight: .semibold), .foregroundColor: UIColor.white]
        let label = "MENU" as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(at: CGPoint(x: box.midX-size.width/2, y: box.midY-size.height/2), withAttributes: attributes)
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

/// Isolated user preference; OFF until explicitly enabled, retained across launches.
final class BoundControllerModePreferences {
    static let key = "bound.controller-mode.v1.enabled"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        set {
            defaults.set(newValue, forKey: Self.key)
            NotificationCenter.default.post(name: BoundAppearancePreferences.didChangeNotification, object: nil)
        }
    }
    static func hidesTouchControls(enabled: Bool, layout: BoundScreenLayout, landscape: Bool) -> Bool {
        enabled && layout == .bound && landscape
    }
}

/// Leaves Delta's screens and external-controller pipeline intact. Only the
/// touchscreen skin's gameplay controls disappear; its real Menu remains.
final class BoundControllerModeSkin: ControllerSkinProtocol {
    let base: ControllerSkinProtocol
    init(base: ControllerSkinProtocol) { self.base = base }
    var name: String { base.name }
    var identifier: String { base.identifier + ".bound-controller-mode" }
    var gameType: GameType { base.gameType }
    var isDebugModeEnabled: Bool { base.isDebugModeEnabled }
    private func isMenu(_ item: DeltaCore.ControllerSkin.Item) -> Bool { item.inputs.allInputs.contains { $0.stringValue == "menu" } }
    func items(for traits: DeltaCore.ControllerSkin.Traits) -> [DeltaCore.ControllerSkin.Item]? {
        guard traits.orientation == .landscape else { return base.items(for: traits) }
        return base.items(for: traits)?.filter(isMenu)
    }
    private func artwork(_ image: UIImage?, traits: DeltaCore.ControllerSkin.Traits) -> UIImage? {
        guard traits.orientation == .landscape, let image else { return image }
        return UIGraphicsImageRenderer(size: image.size).image { context in
            for item in items(for: traits) ?? [] {
                context.cgContext.saveGState()
                context.cgContext.clip(to: item.extendedFrame.applying(.init(scaleX: image.size.width, y: image.size.height)))
                image.draw(at: .zero)
                context.cgContext.restoreGState()
            }
        }
    }
    @MainActor static func cancelTouchInputs(in controller: ControllerView,
                                            preservingExternalInputsFrom controllers: [GameController] = [],
                                            emulatorCore: EmulatorCore? = nil) {
        let releasedPlayer = controller.playerIndex
        controller.cancelTouchInputs()
        // Thumbstick/touchscreen/sustained virtual inputs are separate from the
        // button touch map. Release only this virtual controller's own state.
        for input in Array(controller.sustainedInputs.keys) { controller.unsustain(input) }
        for input in Array(controller.activatedInputs.keys) { controller.deactivate(input) }
        guard let core = emulatorCore, let releasedPlayer,
              core.gameViews.isEmpty || core.gameViews.contains(where: { $0.window?.windowScene?.hasKeyboardFocus == true }) else { return }
        // Delta releases bridge bits per controller rather than aggregating
        // players. Restore same-player external holds after virtual releases.
        // Use the bridge directly: routing sustained inputs through didActivate
        // would deliberately pulse them off for two frames. Never replay actions.
        for external in controllers where external !== controller && external.playerIndex == releasedPlayer {
            var held = external.sustainedInputs
            for (input, value) in external.activatedInputs { held[input] = value }
            for (physical, value) in held {
                guard let mapped = external.mappedInput(for: physical, receiver: core) else { continue }
                let gameInput: Input
                if let standard = StandardGameControllerInput(input: mapped) {
                    guard let resolved = standard.input(for: core.game.type) else { continue }
                    gameInput = resolved
                } else { gameInput = mapped }
                guard gameInput.type == .game(core.game.type), let index = gameInput.intValue else { continue }
                // Match EmulatorCore's discrete threshold and analog saturation.
                var adjustedValue = value
                if !gameInput.isContinuous && value < 0.33 {
                    let sustained = external.sustainedInputs.first { input, _ in
                        guard let mapped = external.mappedInput(for: input, receiver: core) else { return false }
                        return (StandardGameControllerInput(input: mapped)?.input(for: core.game.type) ?? mapped) == gameInput
                    }
                    guard let sustained, sustained.value >= 0.33 else { continue }
                    adjustedValue = sustained.value
                } else if !gameInput.isContinuous && mapped.isContinuous && value > (1.0 - 0.33) {
                    adjustedValue = 1
                }
                core.deltaCore.emulatorBridge.activateInput(index, value: adjustedValue, playerIndex: releasedPlayer)
            }
        }
    }
    func supports(_ traits: DeltaCore.ControllerSkin.Traits) -> Bool { base.supports(traits) }
    func supportedTraits(for traits: DeltaCore.ControllerSkin.Traits) -> DeltaCore.ControllerSkin.Traits? { base.supportedTraits(for: traits) }
    func image(for traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> UIImage? { artwork(base.image(for: traits, preferredSize: preferredSize), traits: traits) }
    func pressedImage(for traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> UIImage? { artwork(base.pressedImage(for: traits, preferredSize: preferredSize), traits: traits) }
    func image(for item: DeltaCore.ControllerSkin.Item, traits: DeltaCore.ControllerSkin.Traits, preferredSize: DeltaCore.ControllerSkin.Size) -> (UIImage, CGSize)? {
        guard traits.orientation != .landscape || isMenu(item) else { return nil }
        return base.image(for: item, traits: traits, preferredSize: preferredSize)
    }
    func isTranslucent(for traits: DeltaCore.ControllerSkin.Traits) -> Bool? { base.isTranslucent(for: traits) }
    func gameScreenFrame(for traits: DeltaCore.ControllerSkin.Traits) -> CGRect? { base.gameScreenFrame(for: traits) }
    func screens(for traits: DeltaCore.ControllerSkin.Traits) -> [DeltaCore.ControllerSkin.Screen]? { base.screens(for: traits) }
    func aspectRatio(for traits: DeltaCore.ControllerSkin.Traits) -> CGSize? { base.aspectRatio(for: traits) }
    func contentSize(for traits: DeltaCore.ControllerSkin.Traits) -> CGSize? { base.contentSize(for: traits) }
    func menuInsets(for traits: DeltaCore.ControllerSkin.Traits) -> UIEdgeInsets? { base.menuInsets(for: traits) }
}
