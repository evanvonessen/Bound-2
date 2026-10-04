import SwiftUI
import UIKit
import AVFoundation
import DeltaCore

@MainActor
final class BoundCompanionState: ObservableObject {
    @Published var selected = 0
    @Published var landscape = false
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
    let sharing = FriendSharingSession(authenticatedMode: true)
    let onboarding = FriendOnboarding()
    let account = BoundFriendAccount()
    let state: BoundCompanionState
    init(state: BoundCompanionState? = nil) { self.state = state ?? BoundCompanionState() }
    private var host: UIHostingController<BoundCompanionPanel>?
    private var controls: UIHostingController<BoundCompanionControls>?
    private var overlay: BoundOverlayView?
    private weak var owner: GameViewController?
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
    #if DEBUG
    private let fixturePresenter = FriendSharingCanvasPresenter()
    #endif
    private lazy var tap = BoundDeltaFrameTap { [weak self] frame in self?.sharing.receivePlaybackFrame(frame) }
    func install(in owner: GameViewController) {
        guard host == nil else { return }
        self.owner = owner
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--bound-ui-reset-layout") {
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
        let panel = BoundCompanionPanel(sharing: sharing, state: state, gameID: (owner.game as? Game)?.identifier ?? "", editingChanged: { [weak self] in self?.notesEditing($0) })
        let host = UIHostingController(rootView: panel)
        host.view.backgroundColor = .clear
        let overlay = BoundOverlayView()
        overlay.accessibilityIdentifier = "bound.companion-container"
        overlay.yieldsTouch = { [weak self, weak overlay] point in
            guard let self, let owner = self.owner, let overlay, !self.isEditingNotes else { return false }
            let local = owner.controllerView.convert(point, from: overlay)
            return owner.controllerView.controlHitFrames.contains { $0.contains(local) }
        }
        owner.addChild(host); owner.view.addSubview(overlay); overlay.addSubview(host.view); host.didMove(toParent: owner)
        self.overlay = overlay; self.host = host
        let controls = UIHostingController(rootView: BoundCompanionControls(sharing: sharing, onboarding: onboarding, account: account, state: state))
        controls.view.backgroundColor = .clear
        owner.addChild(controls); owner.view.addSubview(controls.view); controls.didMove(toParent: owner)
        self.controls = controls
        gestures = BoundPiPGestures(view: owner.view, shouldReceive: { [weak self] touch in self?.shouldReceive(touch) ?? false },
            moved: { [weak self] phase, offset, endX in self?.move(phase, offset: offset, endX: endX) },
            magnified: { [weak self] phase, scale in self?.resize(phase, scale: scale) },
            opacityChanged: { [weak self] phase, dy in self?.fade(phase, dy: dy) })
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
    }
    func layout(in bounds: CGRect, safeArea: UIEdgeInsets, controllerSize: CGSize) -> CGRect? {
        guard let owner else { return nil }
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
            let game = AVMakeRect(aspectRatio: owner.emulatorCore?.preferredRenderingSize ?? CGSize(width: 3, height: 2), insideRect: horizontal)
            let viewport = game.intersection(bounds.inset(by: safeArea))
            let base = CGSize(width: game.width * 0.36, height: game.width * 0.24)
            let geometry = BoundPiPLayout(viewport: viewport, baseSize: base, scale: CGFloat(state.preferences.scale(for: state.content)) * pinchScale)
            self.geometry = geometry
            let center = geometry.clampedCenter(from: state.preferences.corner, translation: translation)
            var panel = CGRect(x: center.x - geometry.size.width / 2, y: center.y - geometry.size.height / 2, width: geometry.size.width, height: geometry.size.height)
            if isEditingNotes {
                let available = bounds.inset(by: safeArea)
                panel = CGRect(x: available.midX - min(400, available.width) / 2, y: available.minY + 4, width: min(400, available.width), height: max(100, min(230, bounds.height - keyboardHeight - available.minY - 8)))
            }
            overlay?.frame = panel
            controls?.view.frame = CGRect(x: horizontal.midX - min(360, horizontal.width) / 2, y: max(safeArea.top, bounds.height - safeArea.bottom - 112), width: min(360, horizontal.width), height: 44)
            overlay?.isHidden = state.hidden
            overlay?.alpha = isEditingNotes ? 1 : liveOpacity ?? state.preferences.opacity(for: state.content)
            owner.gameScreenLayoutBounds = horizontal
            host?.view.frame = overlay?.bounds ?? .zero
            owner.view.bringSubviewToFront(overlay!)
            owner.view.bringSubviewToFront(controls!.view)
            return bounds
        }
        let width = horizontal.width
        let controllerHeight = controllerSize.width > 0 && controllerSize.height > 0 ? width * controllerSize.height / controllerSize.width : width * 0.85625
        let screenHeight = max(60, min(width / 1.5, (bounds.height - safeArea.top - controllerHeight - 56) / 2))
        controls?.view.frame = CGRect(x: horizontal.minX, y: safeArea.top, width: width, height: 44)
        let top = safeArea.top + 48
        overlay?.frame = CGRect(x: horizontal.midX - (state.selected == 0 ? screenHeight * 1.5 : width) / 2, y: top, width: state.selected == 0 ? screenHeight * 1.5 : width, height: screenHeight)
        if isEditingNotes {
            overlay?.frame.size.height = max(screenHeight, min(220, bounds.height - keyboardHeight - top - 8))
        }
        overlay?.isHidden = false; overlay?.alpha = 1
        host?.view.frame = overlay?.bounds ?? .zero
        let gameplay = CGRect(x: horizontal.minX, y: top + screenHeight + 8, width: width, height: max(1, bounds.height - top - screenHeight - 8))
        owner.gameScreenLayoutBounds = nil
        owner.view.bringSubviewToFront(overlay!); owner.view.bringSubviewToFront(controls!.view)
        return gameplay
    }
    /// Called after native Delta layout, so rotation and custom skins use the actual game frame.
    func layoutNativeCompanion(in bounds: CGRect, safeArea: UIEdgeInsets) {
        guard BoundAppearancePreferences().screenLayout == .delta, let owner, let overlay, let controls else { return }
        let game = owner.gameView.convert(owner.gameView.bounds, to: owner.view)
        let viewport = game.intersection(bounds.inset(by: safeArea))
        guard !viewport.isNull, viewport.width > 0, viewport.height > 0 else { overlay.isHidden = true; return }
        let base = CGSize(width: viewport.width * 0.36, height: viewport.width * 0.24)
        let geometry = BoundPiPLayout(viewport: viewport, baseSize: base, scale: CGFloat(state.preferences.scale(for: state.content)) * pinchScale)
        self.geometry = geometry
        let center = geometry.clampedCenter(from: state.preferences.corner, translation: translation)
        var panel = CGRect(x: center.x - geometry.size.width / 2, y: center.y - geometry.size.height / 2, width: geometry.size.width, height: geometry.size.height)
        if isEditingNotes {
            let available = bounds.inset(by: safeArea)
            let top = available.minY + 48
            panel = CGRect(x: available.midX - min(400, available.width) / 2, y: top, width: min(400, available.width), height: max(100, min(230, bounds.height - keyboardHeight - top - 8)))
        }
        overlay.frame = panel; host?.view.frame = overlay.bounds
        overlay.isHidden = state.hidden; overlay.alpha = isEditingNotes ? 1 : liveOpacity ?? state.preferences.opacity(for: state.content)
        let width = min(360, bounds.width - safeArea.left - safeArea.right)
        let y = isEditingNotes ? safeArea.top : state.landscape ? max(safeArea.top, game.maxY - 112) : max(safeArea.top, game.minY - 48)
        controls.view.frame = CGRect(x: bounds.midX - width / 2, y: y, width: width, height: 44)
        owner.view.bringSubviewToFront(overlay); owner.view.bringSubviewToFront(controls.view)
    }
    func bringControlsToFront() { if let controls, let owner { owner.view.bringSubviewToFront(controls.view) } }
    func cancelInteractions() {
        gestures?.cancel(); translation = .zero; pinchScale = 1; liveOpacity = nil
        owner?.controllerView.cancelTouchInputs()
    }
    private func shouldReceive(_ touch: UITouch) -> Bool {
        guard (state.landscape || BoundAppearancePreferences().screenLayout == .delta), !isEditingNotes, !state.showingFriends, !state.showingSettings,
              let owner, let controls, !state.hidden else { return false }
        let p = touch.location(in: owner.view)
        guard !controls.view.frame.contains(p), owner.gameView.convert(owner.gameView.bounds, to: owner.view).contains(p) else { return false }
        let local = touch.location(in: owner.controllerView)
        if owner.controllerView.controlHitFrames.contains(where: { $0.contains(local) }) { return false }
        if state.content != .friend, overlay?.frame.contains(p) == true { return false }
        return true
    }
    private func move(_ phase: UIGestureRecognizer.State, offset: CGSize, endX: CGFloat) {
        guard let geometry else { return }
        if phase == .changed { translation = offset }
        if phase == .ended {
            state.hidden = geometry.hiddenSide(from: state.preferences.corner, translation: offset, endX: endX) != nil
            state.preferences.corner = geometry.destination(from: state.preferences.corner, translation: offset)
            translation = .zero
        } else if phase == .cancelled || phase == .failed { translation = .zero }
        state.refresh()
    }
    private func resize(_ phase: UIGestureRecognizer.State, scale: CGFloat) {
        if phase == .began { initialScale = state.preferences.scale(for: state.content) }
        if phase == .changed { pinchScale = min(1.4 / initialScale, max(0.65 / initialScale, Double(scale))) }
        if phase == .ended { state.preferences.setScale(initialScale * Double(scale), for: state.content); pinchScale = 1 }
        if phase == .cancelled || phase == .failed { pinchScale = 1 }
        state.refresh()
    }
    func fade(_ phase: UIGestureRecognizer.State, dy: CGFloat) {
        if phase == .began { initialOpacity = state.preferences.opacity(for: state.content) }
        if phase == .changed || phase == .ended {
            let height = (geometry?.size.height ?? 160) / CGFloat(state.preferences.scale(for: state.content))
            liveOpacity = BoundPiPPreferences.opacity(start: initialOpacity, verticalTranslation: dy, panelHeight: height)
            if phase == .ended { state.preferences.setOpacity(liveOpacity ?? initialOpacity, for: state.content); liveOpacity = nil }
        }
        if phase == .cancelled || phase == .failed { liveOpacity = nil }
        state.refresh()
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func foreground() { sharing.foreground() }
    func background() { cancelInteractions(); tap.setEnabled(false); sharing.background() }
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
                BoundNotesEditor(gameID: gameID, editingChanged: editingChanged).id(gameID)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Image("PokemonTypeChart").resizable().scaledToFit().frame(width: 600).accessibilityLabel("Pokémon type effectiveness chart")
                }.accessibilityIdentifier("bound.type-chart")
            }
        }.background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: state.landscape ? 8 : 4))
        .onChange(of: sharing.joined) { _ in state.refresh() }
    }
}

private struct BoundCompanionControls: View {
    @ObservedObject var sharing: FriendSharingSession
    @ObservedObject var onboarding: FriendOnboarding
    @ObservedObject var account: BoundFriendAccount
    @ObservedObject var state: BoundCompanionState
    var body: some View {
        HStack(spacing: 4) {
            Picker("Companion panel", selection: $state.selected) {
                Text("Friend").tag(0); Text("Notes").tag(1); Text("Types").tag(2)
            }.pickerStyle(.segmented).accessibilityIdentifier("bound.panel-toggle")
            Button { state.selectionChanged?(); state.showingFriends = true } label: { Image(systemName: "person.2.fill").frame(width: 40, height: 40) }.accessibilityLabel("Friends").accessibilityIdentifier("bound.friends")
            Button { state.selectionChanged?(); state.showingSettings = true } label: { Image(systemName: "gearshape.fill").frame(width: 40, height: 40) }.accessibilityLabel("Playback layout settings").accessibilityIdentifier("bound.layout-settings")
        }.padding(.horizontal, 4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $state.showingFriends) { BoundFriendsSheet(sharing: sharing, onboarding: onboarding, account: account) }
        .sheet(isPresented: $state.showingSettings, onDismiss: { if state.pendingControlEditor { state.pendingControlEditor = false; state.editControls?() } }) { BoundPiPSettings(state: state) }
        .onChange(of: state.selected) { _ in state.selectionChanged?(); state.hidden = false; state.refresh() }
        .onChange(of: sharing.joined) { _ in sharingEnabled() }
        .onChange(of: sharing.active) { _ in sharingEnabled() }
    }
    private func sharingEnabled() { state.sharingChanged?(sharing.joined && sharing.active) }
}

private struct BoundPiPSettings: View {
    @ObservedObject var state: BoundCompanionState
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
                    Text("In Bound landscape or Delta Default, drag with one finger to move. Pinch with two fingers to resize. Slide three fingers up or down to adjust opacity. Swipe to an edge to hide; select a panel to show it again.")
                    ForEach(BoundPiPContent.allCases, id: \.rawValue) { content in
                        VStack(alignment: .leading) {
                            Text("\(content.rawValue.capitalized) transparency: \(Int(state.preferences.transparency(for: content) * 100))%")
                            Slider(value: Binding(get: { state.preferences.transparency(for: content) }, set: { state.preferences.setTransparency($0, for: content); state.refresh() }), in: 0...1, step: 0.05).accessibilityIdentifier("bound.\(content.rawValue)-transparency")
                        }
                    }
                    Button("Show PiP") { state.hidden = false; state.refresh() }
                }
                Section("Delta controls") {
                    Text("Delta's placement is the default. Customize positions separately for portrait and landscape, or reset to Delta.")
                }
            }.navigationTitle("Playback layout").toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Buttons") { state.pendingControlEditor = true; dismiss() }.accessibilityLabel("Button placement").accessibilityIdentifier("bound.button-placement") }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct BoundRemoteCanvas: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct BoundNotesEditor: View {
    let gameID: String
    let editingChanged: (Bool) -> Void
    @State private var text = ""
    @State private var status = "Saved on this device"
    @State private var readable = false
    @FocusState private var editing: Bool
    private let store = BoundNotesStore()
    var body: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $text).focused($editing).disabled(!readable)
                .accessibilityIdentifier("bound.notes-editor")
            HStack {
                Text(status).font(.caption)
                Spacer()
                if editing { Button("Done") { editing = false } }
            }
        }
        .onAppear {
            do { text = try store.read(game: gameID); readable = true }
            catch { status = "Could not read notes. Existing notes are kept." }
        }
        .onChange(of: text) { next in
            guard readable else { return }
            do { try store.write(next, game: gameID); status = "Saved on this device" }
            catch { status = "Could not save notes (16 KB limit)." }
        }
        .onChange(of: editing) { editingChanged($0) }
        .onDisappear { editingChanged(false) }
    }
}

private struct BoundFriendsSheet: View {
    @ObservedObject var sharing: FriendSharingSession
    @ObservedObject var onboarding: FriendOnboarding
    @ObservedObject var account: BoundFriendAccount
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var invite = ""
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
        }.onAppear { onboarding.open(sharing: sharing, existing: { account.session }) }
    }
}
