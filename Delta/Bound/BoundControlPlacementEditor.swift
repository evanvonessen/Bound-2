import UIKit
import DeltaCore

/// Draft-only Bound editor. Preview gestures never activate emulator inputs.
final class BoundControlPlacementEditor: UIViewController {
    private let skin: ControllerSkinProtocol
    private let traits: DeltaCore.ControllerSkin.Traits
    private let canvas: CGSize
    private let sourceFrame: CGRect
    private let landscape: Bool
    private let store: BoundControlPlacementStore
    private let saved: () -> Void
    private var draft: BoundControlLayout
    private var selected: String?
    private var dragStart = CGPoint.zero
    private let preview = UIView()
    private let artwork = UIImageView()
    private let sizeSlider = UISlider()
    private let sizeLabel = UILabel()
    private var controlViews: [String: UIView] = [:]
    private var items: [DeltaCore.ControllerSkin.Item] { (skin.items(for: traits) ?? []).filter { $0.kind == .button || $0.kind == .dPad } }
    init(skin: ControllerSkinProtocol, traits: DeltaCore.ControllerSkin.Traits, canvasSize: CGSize, landscape: Bool, sourceFrame: CGRect? = nil,
         store: BoundControlPlacementStore = .shared, saved: @escaping () -> Void) {
        self.skin = skin; self.traits = traits; canvas = canvasSize; self.sourceFrame = sourceFrame ?? CGRect(origin: .zero, size: canvasSize); self.landscape = landscape; self.store = store; self.saved = saved
        draft = store.read(skin: skin.identifier, landscape: landscape)
        super.init(nibName: nil, bundle: nil)
        selected = items.first?.id
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        title = landscape ? "Landscape Controls" : "Portrait Controls"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16), scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16), scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        let hint = UILabel(); hint.text = "Drag a button or choose it below. Save to apply; Cancel keeps your current layout."; hint.numberOfLines = 0; hint.font = .preferredFont(forTextStyle: .subheadline); stack.addArrangedSubview(hint)
        preview.backgroundColor = .black; preview.clipsToBounds = true; preview.accessibilityIdentifier = "controls.editor.preview"
        artwork.contentMode = .scaleToFill; preview.addSubview(artwork); stack.addArrangedSubview(preview)
        preview.heightAnchor.constraint(equalToConstant: landscape ? 160 : 280).isActive = true
        for item in items {
            let target = UIView(); target.accessibilityLabel = title(for: item) + " control"; target.accessibilityIdentifier = "controls.editor." + item.id + "-preview"; target.isAccessibilityElement = true; target.accessibilityTraits = .button
            target.layer.cornerRadius = 6; target.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
            target.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectControl(_:))))
            preview.addSubview(target); controlViews[item.id] = target
        }
        let choiceScroll = UIScrollView(); choiceScroll.showsHorizontalScrollIndicator = true
        choiceScroll.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let choices = UIStackView(); choices.axis = .horizontal; choices.spacing = 6; choices.translatesAutoresizingMaskIntoConstraints = false
        choiceScroll.addSubview(choices)
        NSLayoutConstraint.activate([choices.leadingAnchor.constraint(equalTo: choiceScroll.contentLayoutGuide.leadingAnchor), choices.trailingAnchor.constraint(equalTo: choiceScroll.contentLayoutGuide.trailingAnchor), choices.topAnchor.constraint(equalTo: choiceScroll.contentLayoutGuide.topAnchor), choices.bottomAnchor.constraint(equalTo: choiceScroll.contentLayoutGuide.bottomAnchor), choices.heightAnchor.constraint(equalTo: choiceScroll.frameLayoutGuide.heightAnchor)])
        for item in items {
            let choice = button(title(for: item), id: "controls.editor.select." + item.id) { [weak self] in self?.selected = item.id; self?.refresh() }
            choice.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true; choices.addArrangedSubview(choice)
        }
        stack.addArrangedSubview(choiceScroll); stack.addArrangedSubview(sizeLabel)
        sizeSlider.minimumValue = 0.7; sizeSlider.maximumValue = 1.4; sizeSlider.accessibilityLabel = "Selected control size"; sizeSlider.accessibilityIdentifier = "controls.editor.size"; sizeSlider.addTarget(self, action: #selector(resize), for: .valueChanged); stack.addArrangedSubview(sizeSlider)
        let nudges = UIStackView(); nudges.distribution = .fillEqually
        for (label, dx, dy) in [("←", -8.0, 0.0), ("↑", 0.0, -8.0), ("↓", 0.0, 8.0), ("→", 8.0, 0.0)] { nudges.addArrangedSubview(button(label, id: "controls.editor.nudge." + label) { [weak self] in self?.move(dx: dx, dy: dy) }) }
        stack.addArrangedSubview(nudges)
        stack.addArrangedSubview(button("Reset selected button", id: "controls.editor.reset-selected") { [weak self] in guard let self, let selected = self.selected else { return }; self.draft.positions.removeValue(forKey: selected); self.refresh() })
        stack.addArrangedSubview(button("Reset to Delta default", id: "controls.editor.reset-all") { [weak self] in self?.draft = .init(); self?.refresh() })
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); refresh() }
    private func title(for item: DeltaCore.ControllerSkin.Item) -> String { item.kind == .dPad ? "D-Pad" : item.inputs.allInputs.map { $0.stringValue.uppercased() }.joined(separator: "+") }
    private var factor: CGFloat { min(preview.bounds.width / max(canvas.width, 1), preview.bounds.height / max(canvas.height, 1)) }
    private var origin: CGPoint { CGPoint(x: (preview.bounds.width - canvas.width * factor) / 2, y: (preview.bounds.height - canvas.height * factor) / 2) }
    private func frame(_ item: DeltaCore.ControllerSkin.Item) -> CGRect { draft.frame(id: item.id, base: item.frame.applying(.init(scaleX: sourceFrame.width, y: sourceFrame.height)).offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY), canvas: canvas, directional: item.kind == .dPad) }
    private func refresh() {
        guard isViewLoaded else { return }
        let decorated = BoundPlacedControllerSkin(base: skin, layout: draft, canvasSize: canvas, sourceFrame: sourceFrame)
        artwork.frame = CGRect(origin: origin, size: CGSize(width: canvas.width * factor, height: canvas.height * factor)); artwork.image = previewImage(decorated)
        for item in items {
            guard let target = controlViews[item.id] else { continue }
            target.frame = frame(item).applying(.init(scaleX: factor, y: factor)).offsetBy(dx: origin.x, dy: origin.y)
            target.layer.borderWidth = selected == item.id ? 3 : 1; target.layer.borderColor = (selected == item.id ? UIColor.systemYellow : UIColor.white.withAlphaComponent(0.4)).cgColor
        }
        sizeSlider.value = Float(selected.flatMap { draft.positions[$0]?.scale } ?? 1)
        sizeLabel.text = "Size: \(Int(sizeSlider.value * 100))%"
    }
    private func previewImage(_ decorated: BoundPlacedControllerSkin) -> UIImage? {
        guard let background = decorated.image(for: traits, preferredSize: .large) else { return nil }
        return UIGraphicsImageRenderer(size: background.size).image { _ in
            background.draw(at: .zero)
            for item in decorated.items(for: traits) ?? [] {
                guard let (image, size) = decorated.image(for: item, traits: traits, preferredSize: .large) else { continue }
                let width = size.width * background.size.width, height = size.height * background.size.height
                image.draw(in: CGRect(x: item.frame.midX * background.size.width - width / 2,
                    y: item.frame.midY * background.size.height - height / 2, width: width, height: height))
            }
        }
    }
    private func button(_ title: String, id: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.accessibilityIdentifier = id; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; button.addAction(UIAction { _ in action() }, for: .touchUpInside); return button
    }
    private func change(center: CGPoint? = nil, scale: Double? = nil) {
        guard let id = selected, let item = items.first(where: { $0.id == id }), canvas.width > 0, canvas.height > 0 else { return }
        let old = frame(item); let point = center ?? CGPoint(x: old.midX, y: old.midY)
        draft.positions[id] = BoundControlPlacement(x: min(1, max(0, point.x / canvas.width)), y: min(1, max(0, point.y / canvas.height)), scale: scale ?? draft.positions[id]?.scale ?? 1)
        // Persist the clamped center so resizing later does not unexpectedly jump.
        let clamped = frame(item); draft.positions[id]?.x = clamped.midX / canvas.width; draft.positions[id]?.y = clamped.midY / canvas.height
        refresh()
    }
    @objc private func selectControl(_ gesture: UITapGestureRecognizer) { selected = controlViews.first(where: { $0.value === gesture.view })?.key; refresh() }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let id = controlViews.first(where: { $0.value === gesture.view })?.key, let item = items.first(where: { $0.id == id }), factor > 0 else { return }
        selected = id
        if gesture.state == .began { let rect = frame(item); dragStart = CGPoint(x: rect.midX, y: rect.midY) }
        if gesture.state == .began || gesture.state == .changed { let delta = gesture.translation(in: preview); change(center: CGPoint(x: dragStart.x + delta.x / factor, y: dragStart.y + delta.y / factor)) }
    }
    @objc private func resize() { change(scale: Double((sizeSlider.value * 20).rounded() / 20)) }
    private func move(dx: Double, dy: Double) { guard let id = selected, let item = items.first(where: { $0.id == id }) else { return }; let rect = frame(item); change(center: CGPoint(x: rect.midX + dx, y: rect.midY + dy)) }
    @objc private func cancel() { dismiss(animated: true) }
    @objc private func save() {
        guard view.window?.windowScene?.activationState == .foregroundActive else { return }
        store.save(draft, skin: skin.identifier, landscape: landscape); saved(); dismiss(animated: true)
    }
}
