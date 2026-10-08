import SwiftUI
import UIKit
import AVFoundation
import Combine
import DeltaCore

@MainActor
final class BoundCompanionState: ObservableObject {
    @Published var selected = 0
    @Published var landscape = false
    @Published var chartTopInset: CGFloat = 0
    @Published var hidden = false
    @Published var showingFriends = false
    @Published var showingSettings = false
    @Published var revision = 0
    @Published var emulationDetails: BoundEmulationDetails?
    #if DEBUG
    @Published var fixtureVideo = false
    #endif
    var displaysFixtureVideo: Bool {
        #if DEBUG
        return fixtureVideo
        #else
        return false
        #endif
    }
    let preferences: BoundPiPPreferences
    init(preferences: BoundPiPPreferences? = nil) { self.preferences = preferences ?? BoundPiPPreferences() }
    var changed: (() -> Void)?
    var pendingControlEditor = false
    var editControls: (() -> Void)?
    var sharingChanged: ((Bool) -> Void)?
    var selectionChanged: (() -> Void)?
    var content: BoundPiPContent { selected == 1 ? .notes : selected == 2 ? .types : .friend }
    func refresh() { revision += 1; changed?() }
}

/// The overlay yields native button touches even if a moved PiP crosses a button.
private final class BoundOverlayView: UIView {
    var yieldsTouch: ((CGPoint) -> Bool)?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if yieldsTouch?(point) == true { return nil }
        return super.hitTest(point, with: event)
    }
}

@MainActor
final class BoundCompanionCoordinator {
    let sharing: FriendSharingSession
    #if DEBUG && targetEnvironment(simulator)
    private let usesLocalPairedFixture: Bool
    #endif
    let onboarding = FriendOnboarding()
    let account = BoundFriendAccount.shared
    let state: BoundCompanionState
    let usesDesktopControls: Bool
    init(state: BoundCompanionState? = nil, usesDesktopControls: Bool = ProcessInfo.processInfo.isiOSAppOnMac) {
        self.state = state ?? BoundCompanionState()
        self.usesDesktopControls = usesDesktopControls
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("--bound-ui-paired-transport"),
           let peer = environment["BOUND_PAIR_PEER"], ["A", "B"].contains(peer),
           let rawPort = environment["BOUND_PAIR_PORT"], let port = Int(rawPort), (1024...65535).contains(port) {
            sharing = FriendSharingSession(configuration: .init(appID: String(repeating: "0", count: 32), channel: "localpair", uid: peer == "A" ? 1 : 2, remoteUID: peer == "A" ? 2 : 1, token: "offline-fixture-not-an-RTC-token"),
                transport: BoundLocalPairedTransport(peer: peer, port: port), authenticatedMode: false)
            usesLocalPairedFixture = true
        } else { sharing = FriendSharingSession(authenticatedMode: true); usesLocalPairedFixture = false }
        #else
        sharing = FriendSharingSession(authenticatedMode: true)
        #endif
    }
    private var host: UIHostingController<BoundCompanionPanel>?
    private var controls: BoundCompanionCycleButton?
    private var desktopControls: BoundDesktopCompanionBar?
    private var subscriptions = Set<AnyCancellable>()
    private var nativeMenuAccessibility: BoundNativeMenuAccessibilityElement?
    private weak var settingsPresenter: UIViewController?
    private var overlay: BoundOverlayView?
    private weak var owner: GameViewController?
    private weak var desktopScene: UIWindowScene?
    private weak var boundCore: EmulatorCore?
    private var gameID = ""
    private var notesPaused = false
    private(set) var isEditingNotes = false
    private var keyboardHeight: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    private var gestures: BoundPiPGestures?
    private var geometry: BoundPiPLayout?
    private var previousScreenLayout: BoundScreenLayout?
    private var translation = CGSize.zero
    private var pinchScale: CGFloat = 1
    private var initialScale = 1.0
    private var initialOpacity = 1.0
    private var liveOpacity: Double?
    private var fadingContent: BoundPiPContent?
    private var resizingContent: BoundPiPContent?
    #if DEBUG
    private let fixturePresenter = FriendSharingCanvasPresenter()
    #endif
    private lazy var tap = BoundDeltaFrameTap { [weak self] frame in self?.sharing.receivePlaybackFrame(frame) }
    func install(in owner: GameViewController) {
        guard host == nil else { return }
        self.owner = owner
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--bound-ui-reset-layout") {
            UserDefaults.standard.removeObject(forKey: BoundControllerModePreferences.key)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("bound.delta.pip.v1.") || key.hasPrefix("bound.controls.v1.") { UserDefaults.standard.removeObject(forKey: key) }
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--bound-ui-screen-layout-bound") { BoundAppearancePreferences().screenLayout = .bound }
        if ProcessInfo.processInfo.arguments.contains("--bound-ui-reset-screen-layout") { UserDefaults.standard.removeObject(forKey: BoundAppearancePreferences.screenLayoutKey) }
        #endif
        state.changed = { [weak owner] in owner?.view.setNeedsLayout() }
        state.editControls = { [weak self] in self?.editControls() }
        state.selectionChanged = { [weak self] in self?.cancelInteractions() }
        state.sharingChanged = { [weak self] in self?.tap.setEnabled($0) }
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let owner = self.owner, let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let local = owner.view.convert(frame, from: nil)
            self.keyboardHeight = owner.presentedViewController == nil ? max(0, owner.view.bounds.maxY - local.minY) : 0
            owner.view.setNeedsLayout()
        })
        observers.append(NotificationCenter.default.addObserver(forName: BoundAppearancePreferences.didChangeNotification, object: nil, queue: .main) { [weak self, weak owner] _ in self?.cancelInteractions(); owner?.view.setNeedsLayout() })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.background() })
        // Restore foreground eligibility without automatically restarting authenticated sharing.
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.foreground() })
        if usesDesktopControls {
            // One Mac window may background/close while another keeps the app active.
            for name in [UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                    guard let self, let scene = event.object as? UIWindowScene, scene === self.desktopScene else { return }
                    self.background()
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] event in
                guard let self, let scene = event.object as? UIWindowScene, scene === self.desktopScene else { return }
                self.foreground()
            })
        }
        let panel = BoundCompanionPanel(sharing: sharing, state: state, gameID: (owner.game as? Game)?.identifier ?? "", editingChanged: { [weak self] in self?.notesEditing($0) })
        let host = UIHostingController(rootView: panel)
        // The coordinator already positions the overlay inside the game viewport.
        // A second inherited home-indicator inset would shrink the visible video
        // and shift the bottom-corner content above its actual PiP frame.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        let overlay = BoundOverlayView()
        overlay.accessibilityIdentifier = "bound.companion-container"
        overlay.yieldsTouch = { [weak self, weak overlay] point in
            guard let self, let owner = self.owner, let overlay, !self.isEditingNotes else { return false }
            if self.usesDesktopControls && owner.controllerView.isHidden { return false }
            let local = owner.controllerView.convert(point, from: overlay)
            return owner.controllerView.controlHitFrames.contains { $0.contains(local) }
        }
        owner.addChild(host); owner.view.addSubview(overlay); overlay.addSubview(host.view); host.didMove(toParent: owner)
        self.overlay = overlay; self.host = host
        let controls = BoundCompanionCycleButton()
        controls.cycle = { [weak self] in
            self?.cyclePanels()
        }
        owner.view.addSubview(controls); self.controls = controls
        if usesDesktopControls {
            let desktop = BoundDesktopCompanionBar()
            desktop.selectPanel = { [weak self] in self?.selectPanel($0) }
            desktop.openMenu = { [weak self, weak owner] in
                guard let self, let owner, owner.presentedViewController == nil else { return }
                owner.view.endEditing(true); self.cancelInteractions()
                owner.gameViewController(owner, handleMenuInputFrom: owner.controllerView)
            }
            desktop.changePiP = { [weak self] action in self?.performDesktopPiPAction(action) }
            owner.view.addSubview(desktop); desktopControls = desktop
        }
        sharing.$joined.combineLatest(sharing.$active).sink { [weak self] joined, active in
            self?.tap.setEnabled(joined && active)
        }.store(in: &subscriptions)
        gestures = BoundPiPGestures(view: owner.view, shouldReceive: { [weak self] touch in self?.shouldReceive(touch) ?? false },
            moved: { [weak self] phase, offset, endX in self?.move(phase, offset: offset, endX: endX) },
            magnified: { [weak self] phase, scale in self?.resize(phase, scale: scale) },
            opacityChanged: { [weak self] phase, dy in self?.fade(phase, dy: dy) },
            allowsOpacity: { [weak self] in self?.allowsOpacityGesture ?? false },
            isCenteredTouch: { [weak self] touch in self?.isCenteredTouch(touch) ?? false },
            isPiPTouch: { [weak self] touch in
                guard let self, let overlay = self.overlay else { return false }
                return overlay.bounds.contains(touch.location(in: overlay))
            })
        bind(core: owner.emulatorCore, gameID: (owner.game as? Game)?.identifier ?? "")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--bound-ui-friend-fixture") {
            // Original generated pixels, offline only. No account/SDK/network/capture.
            var bytes = Data(count: SharingFrame.byteCount)
            bytes.withUnsafeMutableBytes { raw in
                let p = raw.bindMemory(to: UInt8.self)
                for y in 0..<160 { for x in 0..<240 {
                    let i = (y * 240 + x) * 4
                    p[i] = x < 80 ? 255 : 0; p[i + 1] = x >= 80 && x < 160 ? 255 : 0
                    p[i + 2] = x >= 160 ? 255 : 0; p[i + 3] = 255
                } }
            }
            fixturePresenter.present(bytes, in: sharing.remoteView); state.fixtureVideo = true
        }
        #endif
    }
    func bind(core: EmulatorCore?, gameID: String) {
        guard boundCore !== core || self.gameID != gameID else { return }
        cancelInteractions(); tap.setEnabled(false); sharing.stop(); notesPaused = false; isEditingNotes = false; owner?.controllerView.isUserInteractionEnabled = true; self.gameID = gameID
        host?.rootView.gameID = gameID
        guard let core else { boundCore = nil; state.emulationDetails = nil; return }
        state.emulationDetails = BoundEmulationDetails(packageName: core.deltaCore.name, packageIdentifier: core.deltaCore.identifier, packageVersion: core.deltaCore.version)
        boundCore = core
        let previous = core.updateHandler, tap = self.tap
        core.updateHandler = { [weak tap] core in previous?(core); tap?.receive(core) }
        #if DEBUG && targetEnvironment(simulator)
        if usesLocalPairedFixture { sharing.start() }
        #endif
    }
    func layout(in bounds: CGRect, safeArea: UIEdgeInsets, controllerSize: CGSize) -> CGRect? {
        guard let owner else { return nil }
        if usesDesktopControls, let scene = owner.view.window?.windowScene { desktopScene = scene }
        let screenLayout = BoundAppearancePreferences().screenLayout
        if previousScreenLayout != screenLayout { previousScreenLayout = screenLayout; cancelInteractions() }
        let landscape = bounds.width > bounds.height
        if state.landscape != landscape { state.landscape = landscape; cancelInteractions() }
        if screenLayout == .delta {
            owner.gameScreenLayoutBounds = nil
            return nil // Native Delta must lay out first; companion positioning follows it.
        }
        let horizontal = CGRect(x: safeArea.left, y: 0, width: max(1, bounds.width - safeArea.left - safeArea.right), height: bounds.height)
        if landscape {
            // The native game and controls must finish layout before placing PiP.
            owner.gameScreenLayoutBounds = horizontal
            return bounds
        }
        let companionTop = safeArea.top + (usesDesktopControls ? 52 : 0)
        let geometry = BoundPortraitScreenGeometry(bounds: bounds, safeTop: companionTop,
            controllerSize: controllerSize, gameAspect: owner.emulatorCore?.preferredRenderingSize ?? CGSize(width: 3, height: 2))
        overlay?.frame = geometry.friend
        if state.content != .friend { overlay?.frame = CGRect(x: bounds.minX, y: geometry.friend.minY, width: bounds.width, height: geometry.friend.height) }
        if state.content == .types {
            overlay?.frame = BoundTypeChartGeometry.portraitViewport(bounds: bounds, gameFrame: geometry.game)
            if state.chartTopInset != companionTop { state.chartTopInset = companionTop }
        }
        if isEditingNotes {
            overlay?.frame.size.height = max(geometry.friend.height, min(220, bounds.height - keyboardHeight - geometry.friend.minY - 8))
        }
        overlay?.isHidden = false; overlay?.alpha = 1
        host?.view.frame = overlay?.bounds ?? .zero
        owner.gameScreenLayoutBounds = geometry.game
        owner.view.bringSubviewToFront(overlay!); layoutCycleButton(bounds: bounds, safeArea: safeArea)
        return nil // Native Delta's full-viewport controller layout remains untouched.
    }
    func bringControlsToFront() {
        guard let owner else { return }
        layoutCycleButton(bounds: owner.view.bounds, safeArea: owner.view.safeAreaInsets)
        if state.landscape || BoundAppearancePreferences().screenLayout == .delta {
            layoutFloatingPanel()
        }
        sharing.setRemotePresentationEnabled(state.content == .friend && overlay?.isHidden == false)
        if let controls { owner.view.bringSubviewToFront(controls) }
        if let desktopControls { owner.view.bringSubviewToFront(desktopControls) }
    }
    /// One final placement, using the settled native viewport and actual hit regions.
    private func layoutFloatingPanel() {
        guard let owner, let overlay, let controls else { return }
        let game = owner.gameView.convert(owner.gameView.bounds, to: owner.view)
        let viewport = game.intersection(owner.view.bounds.inset(by: owner.view.safeAreaInsets))
        guard !viewport.isNull, viewport.width > 0, viewport.height > 0 else { overlay.isHidden = true; return }
        var occupied = usesDesktopControls && owner.controllerView.isHidden ? [] : owner.controllerView.controlHitFrames.map { owner.controllerView.convert($0, to: owner.view) }
        if !controls.isHidden { occupied.append(controls.frame) }
        if let desktopControls { occupied.append(desktopControls.frame) }
        #if DEBUG && targetEnvironment(simulator)
        owner.gameView.accessibilityValue = "pip-hit-obstacles=" + occupied.map { rect in
            let screen = owner.view.convert(rect, to: nil)
            return String(format: "%.2f,%.2f,%.2f,%.2f", screen.minX, screen.minY, screen.width, screen.height)
        }.joined(separator: "|")
        #endif
        let layout = BoundPiPLayout(viewport: viewport,
            baseSize: companionBaseSize(width: viewport.width * 0.36),
            scale: CGFloat(state.preferences.scale(for: state.content)) * pinchScale, occupied: occupied)
        geometry = layout
        let corner = state.preferences.corner(for: state.content)
        // Follow the finger continuously; collision-free corner placement happens
        // on release. The overlay always yields touches to native controls.
        let center = translation == .zero ? layout.center(corner) : layout.dragCenter(from: corner, translation: translation)
        var panel = CGRect(x: center.x - layout.size.width / 2, y: center.y - layout.size.height / 2,
                           width: layout.size.width, height: layout.size.height)
        if isEditingNotes {
            let available = owner.view.bounds.inset(by: owner.view.safeAreaInsets)
            let top = max(available.minY + (state.landscape ? 4 : 48),
                          desktopControls.map { $0.frame.maxY + 8 } ?? available.minY)
            panel = CGRect(x: available.midX - min(400, available.width) / 2, y: top,
                           width: min(400, available.width),
                           height: max(100, min(230, owner.view.bounds.height - keyboardHeight - top - 8)))
        }
        overlay.frame = panel
        host?.view.frame = overlay.bounds
        overlay.isHidden = state.hidden || layout.size.width == 0 || layout.size.height == 0
        overlay.alpha = isEditingNotes ? 1 : liveOpacity ?? state.preferences.opacity(for: state.content)
        owner.view.bringSubviewToFront(overlay)
    }
    private func layoutCycleButton(bounds: CGRect, safeArea: UIEdgeInsets) {
        if let desktopControls {
            controls?.isHidden = true
            desktopControls.frame = BoundDesktopCompanionLayout.toolbar(in: bounds.inset(by: safeArea))
            desktopControls.configure(state: state, floating: state.landscape || BoundAppearancePreferences().screenLayout == .delta, editingNotes: isEditingNotes)
            return
        }
        guard let owner, let controls, let skin = owner.controllerView.controllerSkin,
              let traits = owner.controllerView.controllerSkinTraits,
              let menu = skin.items(for: traits)?.first(where: { $0.inputs.allInputs.contains(where: { $0.stringValue == "menu" }) }) else { controls?.isHidden = true; return }
        let local = menu.frame.applying(.init(scaleX: owner.controllerView.bounds.width, y: owner.controllerView.bounds.height))
        let frame = owner.controllerView.convert(local, to: owner.view)
        let menuAccessibility = nativeMenuAccessibility ?? BoundNativeMenuAccessibilityElement(accessibilityContainer: owner.controllerView)
        menuAccessibility.accessibilityIdentifier = "bound.native-menu"
        menuAccessibility.accessibilityLabel = "Menu"
        menuAccessibility.accessibilityTraits = .button
        menuAccessibility.accessibilityFrameInContainerSpace = local
        menuAccessibility.activate = { [weak owner] in
            guard let owner else { return false }
            owner.controllerView.cancelTouchInputs()
            owner.gameViewController(owner, handleMenuInputFrom: owner.controllerView)
            return true
        }
        var accessibleControls: [UIAccessibilityElement] = [menuAccessibility]
        for input in ["l", "r"] {
            guard let item = skin.items(for: traits)?.first(where: { $0.inputs.allInputs.contains(where: { $0.stringValue == input }) }) else { continue }
            let element = UIAccessibilityElement(accessibilityContainer: owner.controllerView)
            element.accessibilityIdentifier = "bound.native-" + input
            element.accessibilityLabel = input.uppercased() + " shoulder control"
            element.accessibilityFrameInContainerSpace = item.frame.applying(.init(scaleX: owner.controllerView.bounds.width, y: owner.controllerView.bounds.height))
            accessibleControls.append(element)
        }
        owner.controllerView.accessibilityElements = accessibleControls
        nativeMenuAccessibility = menuAccessibility
        let controller = owner.controllerView.convert(owner.controllerView.bounds, to: owner.view)
        let occupied = owner.controllerView.controlHitFrames.map { owner.controllerView.convert($0, to: owner.view) }
        controls.isHidden = false
        let right = skin.items(for: traits)?.first(where: { $0.inputs.allInputs.contains(where: { $0.stringValue == "r" }) })
        let rightFrame = right.map { owner.controllerView.convert($0.extendedFrame.applying(.init(scaleX: owner.controllerView.bounds.width, y: owner.controllerView.bounds.height)), to: owner.view) }
        let menuHitSize = menu.extendedFrame.applying(.init(scaleX: owner.controllerView.bounds.width, y: owner.controllerView.bounds.height)).size
        let boundPortrait = !state.landscape && BoundAppearancePreferences().screenLayout == .bound
        let select = skin.items(for: traits)?.first { $0.inputs.allInputs.contains { $0.stringValue == "select" } }
        let selectArtwork = boundPortrait && BoundAppearancePreferences().theme != .minimal
            ? select.flatMap { skin.image(for: $0, traits: traits, preferredSize: .large)?.0 } : nil
        controls.configure(menuFrame: frame, controllerFrame: controller, landscape: state.landscape,
            minimal: BoundAppearancePreferences().theme == .minimal, content: state.content,
            canvas: bounds.inset(by: safeArea), occupied: occupied, rightShoulderFrame: rightFrame, menuHitSize: menuHitSize, boundPortrait: boundPortrait, selectArtwork: selectArtwork,
            rightControlGutter: owner.boundLandscapeControlGutter(),
            menuHitFrame: owner.controllerView.convert(menu.extendedFrame.applying(.init(scaleX: owner.controllerView.bounds.width, y: owner.controllerView.bounds.height)), to: owner.view))
        controls.accessibilityHint = state.hidden ? "Restores the hidden panel" : "Cycles Friend, Notes, and Types"
        owner.view.bringSubviewToFront(controls)
    }
    func presentFriends(from presenter: UIViewController) {
        cancelInteractions(); state.showingFriends = true
        let host = UIHostingController(rootView: BoundFriendsSheet(sharing: sharing, onboarding: onboarding, account: account, closed: { [weak self] in self?.state.showingFriends = false }))
        presenter.present(host, animated: true)
    }
    func presentSettings(from presenter: UIViewController) {
        cancelInteractions(); state.showingSettings = true; settingsPresenter = presenter
        let host = UIHostingController(rootView: BoundPiPSettings(state: state, closed: { [weak self] in
            guard let self else { return }; self.state.showingSettings = false
            if self.state.pendingControlEditor { self.state.pendingControlEditor = false
                DispatchQueue.main.async { [weak self] in
                    guard let self, let presenter = self.settingsPresenter else { return }
                    if let modal = presenter.presentedViewController, let transition = modal.transitionCoordinator {
                        transition.animate(alongsideTransition: nil) { [weak self, weak presenter] _ in
                            guard let presenter else { return }; self?.owner?.showBoundControlPlacement(from: presenter)
                        }
                    } else { self.owner?.showBoundControlPlacement(from: presenter) }
                }
            }
        }))
        presenter.present(host, animated: true)
    }
    func cancelInteractions() {
        gestures?.cancel(); translation = .zero; pinchScale = 1; liveOpacity = nil
        fadingContent = nil; resizingContent = nil
        owner?.controllerView.cancelTouchInputs()
    }
    func cyclePanels() {
        owner?.view.endEditing(true)
        cancelInteractions()
        if !state.hidden { state.selected = (state.selected + 1) % 3 }
        state.hidden = false; state.refresh()
    }
    func selectPanel(_ selected: Int) {
        guard (0...2).contains(selected) else { return }
        owner?.view.endEditing(true); cancelInteractions()
        state.selected = selected; state.hidden = false; state.refresh()
    }
    func performDesktopPiPAction(_ action: BoundDesktopPiPAction) {
        guard usesDesktopControls, !isEditingNotes,
              state.landscape || BoundAppearancePreferences().screenLayout == .delta else { return }
        cancelInteractions()
        switch action {
        case .toggleVisibility: state.hidden.toggle()
        case .corner(let corner): state.preferences.setCorner(corner, for: state.content); state.hidden = false
        case .scale(let scale): state.preferences.setScale(scale, for: state.content); state.hidden = false
        case .opacity(let opacity): state.preferences.setOpacity(opacity, for: state.content); state.hidden = false
        }
        state.refresh()
    }
    var allowsOpacityGesture: Bool { state.landscape && state.content != .types && !isEditingNotes }
    private func companionBaseSize(width: CGFloat) -> CGSize {
        let image = state.landscape && state.content == .types ? UIImage(named: "PokemonTypeChart")?.size : nil
        let aspect = image.map { $0.width / max(1, $0.height) } ?? 1.5
        return CGSize(width: width, height: width / max(0.001, aspect))
    }
    private func isCenteredTouch(_ touch: UITouch) -> Bool {
        guard let owner, let overlay else { return false }
        let point = touch.location(in: owner.view)
        let game = owner.gameView.convert(owner.gameView.bounds, to: owner.view)
        return game.insetBy(dx: game.width * 0.2, dy: game.height * 0.15).contains(point)
            && !overlay.frame.contains(point)
    }
    private func shouldReceive(_ touch: UITouch) -> Bool {
        guard (state.landscape || (BoundAppearancePreferences().screenLayout == .delta && state.content != .types)), !isEditingNotes, !state.showingFriends, !state.showingSettings,
              let owner, let controls, !state.hidden else { return false }
        let p = touch.location(in: owner.view)
        guard !controls.frame.contains(p), owner.gameView.convert(owner.gameView.bounds, to: owner.view).contains(p) else { return false }
        var target = touch.view
        while let view = target, view !== owner.view {
            if view is UITextView || view is UITextField || view is UIControl { return false }
            target = view.superview
        }
        let local = touch.location(in: owner.controllerView)
        if !(usesDesktopControls && owner.controllerView.isHidden), owner.controllerView.controlHitFrames.contains(where: { $0.contains(local) }) { return false }
        return true
    }
    private func move(_ phase: UIGestureRecognizer.State, offset: CGSize, endX: CGFloat) {
        guard let geometry else { return }
        if phase == .began || phase == .changed { translation = offset }
        if phase == .ended {
            let corner = state.preferences.corner(for: state.content)
            state.hidden = geometry.hiddenSide(from: corner, translation: offset, endX: endX) != nil
            state.preferences.setCorner(geometry.destination(from: corner, translation: offset), for: state.content)
            translation = .zero
        } else if phase == .cancelled || phase == .failed { translation = .zero }
        state.refresh()
    }
    func resize(_ phase: UIGestureRecognizer.State, scale: CGFloat) {
        if phase == .began { resizingContent = state.content; initialScale = state.preferences.scale(for: state.content); pinchScale = 1 }
        guard let content = resizingContent, content == state.content else { pinchScale = 1; resizingContent = nil; return }
        // UIKit may recognize a short gesture immediately before its release.
        // Consume the valid begin/end sample too, even with no changed callback.
        if [.began, .changed, .ended].contains(phase), scale.isFinite {
            pinchScale = min(1.4 / initialScale, max(0.65 / initialScale, Double(scale)))
        }
        if phase == .ended { state.preferences.setScale(initialScale * Double(pinchScale), for: content); pinchScale = 1; resizingContent = nil }
        if phase == .cancelled || phase == .failed { pinchScale = 1; resizingContent = nil }
        state.refresh()
    }
    func fade(_ phase: UIGestureRecognizer.State, dy: CGFloat) {
        guard allowsOpacityGesture else { liveOpacity = nil; fadingContent = nil; return }
        if phase == .began { fadingContent = state.content; initialOpacity = state.preferences.opacity(for: state.content); liveOpacity = initialOpacity }
        guard let content = fadingContent, content == state.content else { liveOpacity = nil; fadingContent = nil; return }
        if [.began, .changed, .ended].contains(phase) {
            let height = (geometry?.size.height ?? 160) / CGFloat(state.preferences.scale(for: state.content))
            liveOpacity = BoundPiPPreferences.opacity(start: initialOpacity, verticalTranslation: dy, panelHeight: height)
        }
        if phase == .ended { state.preferences.setOpacity(liveOpacity ?? initialOpacity, for: content); liveOpacity = nil; fadingContent = nil }
        if phase == .cancelled || phase == .failed { liveOpacity = nil; fadingContent = nil }
        state.refresh()
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func foreground() {
        sharing.foreground()
        #if DEBUG && targetEnvironment(simulator)
        if usesLocalPairedFixture { sharing.start() }
        #endif
    }
    func background() { cancelInteractions(); tap.setEnabled(false); sharing.background(); onboarding.close() }
    func stop() {
        cancelInteractions(); tap.setEnabled(false); sharing.stop(); onboarding.close()
        notesPaused = false; isEditingNotes = false; owner?.controllerView.isUserInteractionEnabled = true; host?.view.endEditing(true)
    }
    private func notesEditing(_ editing: Bool) {
        isEditingNotes = editing; owner?.controllerView.cancelTouchInputs()
        owner?.controllerView.isUserInteractionEnabled = !editing
        owner?.view.setNeedsLayout()
        guard let core = owner?.emulatorCore else { return }
        if editing {
            notesPaused = core.state == .running
            if notesPaused { core.pause() }
        } else {
            let resume = notesPaused; notesPaused = false
            if resume, core.state == .paused, owner?.view.window != nil,
               UIApplication.shared.applicationState == .active, let owner,
               owner.gameViewControllerShouldResumeEmulation(owner) { core.resume() }
        }
    }
    private func editControls() {
        // Wired to the native skin placement editor below once its active traits are available.
        owner?.showBoundControlPlacement()
    }
}

struct BoundCompanionPanel: View {
    @ObservedObject var sharing: FriendSharingSession
    @ObservedObject var state: BoundCompanionState
    var gameID: String
    let editingChanged: (Bool) -> Void
    var body: some View {
        Group {
            if state.selected == 0 {
                ZStack {
                    Color.black
                    BoundRemoteCanvas(view: sharing.remoteView).opacity(sharing.remoteVisible || state.displaysFixtureVideo ? 1 : 0)
                    if !sharing.remoteVisible && !state.displaysFixtureVideo { Text(sharing.active ? "Waiting for friend" : "Connect a friend").foregroundStyle(.white).font(.callout) }
                }.accessibilityIdentifier("bound.friend-screen")
            } else if state.selected == 1 {
                BoundNotesEditor(gameID: gameID, floating: state.landscape, editingChanged: editingChanged).id(gameID)
            } else {
                if state.landscape {
                    Image("PokemonTypeChart").resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Pokémon type effectiveness chart")
                        .accessibilityIdentifier("bound.type-chart")
                } else { BoundTypeChartView(topInset: state.chartTopInset, constrainsPan: BoundAppearancePreferences().screenLayout == .bound) }
            }
        }.background(state.content == .types ? Color.black : Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: state.landscape ? 8 : state.content == .types ? 0 : 4))
        .onChange(of: sharing.joined) { _ in state.refresh() }
    }
}

private struct BoundPiPSettings: View {
    @ObservedObject var state: BoundCompanionState
    var closed: () -> Void = {}
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            Form {
                BoundAppearanceSettings()
                Section("Emulation backend") {
                    if let details = state.emulationDetails {
                        LabeledContent("Active package", value: details.packageName).accessibilityIdentifier("bound.emulation-package")
                        #if DEBUG
                        LabeledContent("Package identifier", value: details.packageIdentifier).font(.caption)
                        LabeledContent("Package build", value: details.packageBuild).accessibilityIdentifier("bound.emulation-package-build")
                        #else
                        LabeledContent("Package version", value: details.packageVersion ?? "Source build").accessibilityIdentifier("bound.emulation-package-build")
                        #endif
                        if let engine = details.engineName {
                            LabeledContent("Emulator engine", value: engine).accessibilityIdentifier("bound.emulation-engine")
                            #if DEBUG
                            if let revision = details.engineRevision {
                                LabeledContent("Engine source", value: "Pinned " + String(revision.prefix(12))).accessibilityIdentifier("bound.emulation-engine-build")
                            }
                            #endif
                        }
                        #if DEBUG
                        Text("DeltaCore pinned source " + String(BoundEmulationDetails.deltaCoreRevision.prefix(12))).font(.caption)
                        Text("Delta upstream source " + String(BoundEmulationDetails.deltaUpstreamRevision.prefix(12))).font(.caption)
                        #endif
                        Text("Screen layout changes presentation only; it does not switch the emulator engine.").font(.footnote).foregroundStyle(.secondary)
                    } else { Text("No emulation package is active.") }
                }
                Section("Picture in picture") {
                    if ProcessInfo.processInfo.isiOSAppOnMac {
                        Text("Use the companion toolbar or Command–1, Command–2 and Command–3 to select Friends, Notes and Types. The PiP menu changes corner, size and opacity with a mouse or trackpad. Command–Shift–P hides or restores a floating panel. Use Menu for saves, Friends and Bound settings.")
                    } else {
                        Text("In landscape, drag a panel with one finger to move it, or pinch on it with two fingers to resize. Slide two fingers vertically in the center of the game to change Friend or Notes opacity. Types stays opaque. Swipe a panel to an edge to hide; tap the companion button to restore it. Portrait Types zooms and pans its chart content.")
                    }
                    ForEach([BoundPiPContent.friend, .notes], id: \.rawValue) { content in
                        VStack(alignment: .leading) {
                            Text("\(content.rawValue.capitalized) transparency: \(Int(state.preferences.transparency(for: content) * 100))%")
                            Slider(value: Binding(get: { state.preferences.transparency(for: content) }, set: { state.preferences.setTransparency($0, for: content); state.refresh() }), in: 0...1, step: 0.05).accessibilityIdentifier("bound.\(content.rawValue)-transparency")
                        }
                    }
                    Button("Show PiP") { state.hidden = false; state.refresh() }
                }
                Section("Controls") {
                    Text("Classic placement is the default. Customize positions separately for portrait and landscape, or reset to defaults.")
                }
            }.navigationTitle("Bound Settings").toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Buttons") { state.pendingControlEditor = true; dismiss() }.accessibilityLabel("Button placement").accessibilityIdentifier("bound.button-placement") }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }.onDisappear(perform: closed)
    }
}

private struct BoundRemoteCanvas: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct BoundNotesEditor: View {
    let gameID: String
    let floating: Bool
    let editingChanged: (Bool) -> Void
    @State private var text = ""
    @State private var status = ""
    @State private var readable = false
    @State private var editing = false
    @FocusState private var classicEditing: Bool
    @AppStorage(BoundAppearancePreferences.screenLayoutKey) private var screenLayoutRaw = BoundAppearancePreferences.defaultScreenLayout.rawValue
    private let store = BoundNotesStore()
    private var usesBoundArrangement: Bool { (BoundScreenLayout(rawValue: screenLayoutRaw) ?? BoundAppearancePreferences.defaultScreenLayout) == .bound }
    var body: some View {
        VStack(alignment: .leading) {
            if usesBoundArrangement {
                ZStack(alignment: .topLeading) {
                    BoundNotesTextView(text: $text, editing: Binding(get: { editing }, set: { editing = $0 }))
                        .disabled(!readable)
                        .allowsHitTesting(!floating || editing)
                    if readable && text.isEmpty && !editing {
                        Text("Tap to add notes")
                            .font(BoundNotesFont.swiftUIFont()).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 8)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("bound.notes-placeholder")
                    }
                }.accessibilityElement(children: .contain)
            } else {
                TextEditor(text: $text).focused($classicEditing).disabled(!readable)
                    .accessibilityIdentifier("bound.notes-editor")
                    .allowsHitTesting(!floating || editing)
            }
            if !status.isEmpty || editing {
                HStack {
                    if !status.isEmpty { Text(status).font(.caption) }
                    Spacer()
                    if editing { Button("Done") { editing = false; classicEditing = false }
                        .font(usesBoundArrangement ? BoundNotesFont.swiftUIFont(pointSize: 12, relativeTo: .callout) : .body)
                        .frame(minWidth: usesBoundArrangement ? 44 : nil, minHeight: usesBoundArrangement ? 44 : nil) }
                }
                .padding(usesBoundArrangement ? 8 : 0)
                .background(usesBoundArrangement ? Color.black : Color.clear)
                .foregroundStyle(usesBoundArrangement ? Color.white : Color.primary)
            }
        }
        .overlay {
            if floating && !editing && readable {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { editing = true; classicEditing = !usesBoundArrangement }
                    .accessibilityLabel("Edit notes")
                    .accessibilityIdentifier("bound.notes-preview")
            }
        }
        .onAppear {
            do { text = try store.read(game: gameID); readable = true }
            catch { status = "Could not read notes. Existing notes are kept." }
        }
        .onChange(of: text) { next in
            guard readable else { return }
            do { try store.write(next, game: gameID); status = "" }
            catch { status = "Could not save notes (16 KB limit)." }
        }
        .onChange(of: classicEditing) { if !usesBoundArrangement { editing = $0 } }
        .onChange(of: screenLayoutRaw) { _ in editing = false; classicEditing = false }
        .onChange(of: editing) { editingChanged($0) }
        .onDisappear { editingChanged(false) }
    }
}

/// Bound-only editor: explicit UIKit traits disable both correction and spelling underlines.
/// The native Delta arrangement continues to use its existing SwiftUI TextEditor.
struct BoundNotesTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var editing: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = BoundNotesFont.uiFont()
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.backgroundColor = .systemBackground
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.accessibilityLabel = "Notes"
        view.accessibilityIdentifier = "bound.notes-editor"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = context.environment.isEnabled
        view.isSelectable = context.environment.isEnabled
        view.isUserInteractionEnabled = context.environment.isEnabled
        // Avoid disturbing the selection or marked text during ordinary typing.
        if view.text != text { view.text = text }
        if editing && !view.isFirstResponder {
            DispatchQueue.main.async { if self.editing { view.becomeFirstResponder() } }
        } else if !editing && view.isFirstResponder { view.resignFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BoundNotesTextView
        init(_ parent: BoundNotesTextView) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { if !parent.editing { parent.editing = true } }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidEndEditing(_ textView: UITextView) { if parent.editing { parent.editing = false } }
    }
}

private struct BoundFriendsSheet: View {
    @ObservedObject var sharing: FriendSharingSession
    @ObservedObject var onboarding: FriendOnboarding
    @ObservedObject var account: BoundFriendAccount
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var invite = ""
    var closed: () -> Void = {}
    var body: some View {
        NavigationStack {
            Form {
                Section("Bound account") {
                    if account.session == nil {
                        TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                        SecureField("Password", text: $password)
                        Button("Sign in") {
                            let entered = password; password = ""
                            Task { await account.signIn(email: email, password: entered); onboarding.synchronizeAccount() }
                        }.disabled(account.busy || email.isEmpty || password.isEmpty)
                    } else {
                        Button("Sign out") { sharing.stop(); onboarding.signOut(); account.signOut() }
                    }
                    Text(account.status).font(.caption)
                }
                if account.session != nil {
                    Section("Friends") {
                        Text(onboarding.message).font(.caption)
                        ForEach(onboarding.rooms) { room in
                            Button(room.displayName) { onboarding.select(room) }
                                .disabled(onboarding.busy)
                        }
                        Button("Refresh") { onboarding.refresh() }.disabled(onboarding.busy)
                        if onboarding.selected != nil {
                            Button(sharing.active ? "Stop sharing" : "Start sharing") {
                                if sharing.active { sharing.stop() } else { sharing.start() }
                            }
                        }
                    }
                    Section("Add a friend") {
                        TextField("Your display name", text: $name)
                        Button("Create invite") { onboarding.create(name: name) }.disabled(onboarding.busy || name.isEmpty)
                        if let code = onboarding.inviteCode {
                            Text(code).textSelection(.enabled)
                        }
                        TextField("Friend's invite code", text: $invite).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Accept invite") { onboarding.accept(code: invite, name: name); invite = "" }
                            .disabled(onboarding.busy || invite.count != 16 || name.isEmpty)
                    }
                }
            }.navigationTitle("Friends")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { onboarding.open(sharing: sharing, existing: { account.session }) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { onboarding.open(sharing: sharing, existing: { account.session }) }
            else { onboarding.close() }
        }
        .onDisappear { onboarding.close(); closed() }
    }
}


/// Pointer controls for Delta's iPad binary running on Apple silicon. No Catalyst UI.
enum BoundDesktopPiPAction {
    case toggleVisibility
    case corner(BoundPiPCorner)
    case scale(Double)
    case opacity(Double)
}

@MainActor
final class BoundDesktopCompanionBar: UIVisualEffectView {
    var selectPanel: ((Int) -> Void)?
    var openMenu: (() -> Void)?
    var changePiP: ((BoundDesktopPiPAction) -> Void)?
    private let panels = UISegmentedControl(items: ["Friends", "Notes", "Types"])
    private let menuButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let stack = UIStackView()

    init() {
        super.init(effect: UIBlurEffect(style: .systemChromeMaterial))
        accessibilityIdentifier = "bound.desktop-toolbar"
        layer.cornerRadius = 12; clipsToBounds = true
        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        menuButton.accessibilityLabel = "Game menu"
        menuButton.accessibilityIdentifier = "bound.desktop-menu"
        menuButton.addAction(UIAction { [weak self] _ in self?.openMenu?() }, for: .touchUpInside)
        panels.accessibilityIdentifier = "bound.desktop-panels"
        panels.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.selectPanel?(self.panels.selectedSegmentIndex)
        }, for: .valueChanged)
        pipButton.setImage(UIImage(systemName: "pip"), for: .normal)
        pipButton.accessibilityLabel = "Picture in picture options"
        pipButton.accessibilityIdentifier = "bound.desktop-pip"
        pipButton.showsMenuAsPrimaryAction = true
        stack.axis = .horizontal; stack.alignment = .center; stack.spacing = 8
        [menuButton, panels, pipButton].forEach(stack.addArrangedSubview)
        [menuButton, pipButton].forEach { $0.widthAnchor.constraint(equalToConstant: 36).isActive = true }
        contentView.addSubview(stack)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews(); stack.frame = contentView.bounds.insetBy(dx: 8, dy: 4)
    }
    func configure(state: BoundCompanionState, floating: Bool, editingNotes: Bool) {
        panels.selectedSegmentIndex = state.selected
        pipButton.isEnabled = floating && !editingNotes
        let action: (String, BoundDesktopPiPAction, Bool) -> UIAction = { [weak self] title, command, selected in
            UIAction(title: title, state: selected ? .on : .off) { [weak self] _ in self?.changePiP?(command) }
        }
        let corners: [(String, BoundPiPCorner)] = [("Top left", .topLeft), ("Top right", .topRight), ("Bottom left", .bottomLeft), ("Bottom right", .bottomRight)]
        let corner = UIMenu(title: "Corner", children: corners.map {
            action($0.0, .corner($0.1), state.preferences.corner(for: state.content) == $0.1)
        })
        let size = UIMenu(title: "Size", children: [0.65, 0.85, 1, 1.2, 1.4].map {
            action("\(Int($0 * 100))%", .scale($0), abs(state.preferences.scale(for: state.content) - $0) < 0.001)
        })
        var items: [UIMenuElement] = [action(state.hidden ? "Show panel" : "Hide panel", .toggleVisibility, false), corner, size]
        if state.content != .types {
            items.append(UIMenu(title: "Opacity", children: [0.25, 0.5, 0.75, 1].map {
                action("\(Int($0 * 100))%", .opacity($0), abs(state.preferences.opacity(for: state.content) - $0) < 0.001)
            }))
        }
        pipButton.menu = UIMenu(children: items)
    }
}
