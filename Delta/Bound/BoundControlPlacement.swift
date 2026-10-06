import Foundation

/// Bound's normalized drag/resize placements, kept separately per orientation and skin.
struct BoundControlPlacement: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double
    var isValid: Bool { x.isFinite && y.isFinite && scale.isFinite && (0...1).contains(x) && (0...1).contains(y) && (0.7...1.4).contains(scale) }
}
struct BoundControlLayout: Codable, Equatable {
    var positions: [String: BoundControlPlacement] = [:]
    var isValid: Bool { positions.count <= 32 && positions.allSatisfy { !$0.key.isEmpty && $0.key.utf8.count <= 128 && $0.value.isValid } }
    func frame(id: String, base: CGRect, canvas: CGSize, directional: Bool) -> CGRect {
        guard let value = positions[id], value.isValid, canvas.width > 0, canvas.height > 0 else { return base }
        let minimum: CGFloat = directional ? 132 : 44
        let width = min(canvas.width, max(minimum, base.width * value.scale))
        let height = min(canvas.height, max(minimum, base.height * value.scale))
        let x = min(max(value.x * canvas.width, width / 2), canvas.width - width / 2)
        let y = min(max(value.y * canvas.height, height / 2), canvas.height - height / 2)
        return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }
}
final class BoundControlPlacementStore: @unchecked Sendable {
    static let shared = BoundControlPlacementStore()
    private let defaults: UserDefaults
    private let cacheLock = NSLock()
    private var cache: [String: (data: Data?, layout: BoundControlLayout)] = [:]
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(skin: String, landscape: Bool) -> String { "bound.controls.v1." + skin + (landscape ? ".landscape" : ".portrait") }
    func read(skin: String, landscape: Bool) -> BoundControlLayout {
        let key = key(skin: skin, landscape: landscape)
        let data = defaults.data(forKey: key)
        guard (data?.count ?? 0) <= 16384 else { return .init() }
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = cache[key], cached.data == data { return cached.layout }
        let decoded = data.flatMap { try? JSONDecoder().decode(BoundControlLayout.self, from: $0) }
        let layout = decoded.flatMap { $0.isValid ? $0 : nil } ?? .init()
        // Compare stored bytes so another editor/store or an explicit defaults
        // reset invalidates the cache without an observer or a polling timer.
        if cache.count >= 32 { cache.removeAll(keepingCapacity: true) }
        cache[key] = (data, layout)
        return layout
    }

    func save(_ layout: BoundControlLayout, skin: String, landscape: Bool) {
        guard layout.isValid, let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: key(skin: skin, landscape: landscape))
    }
}
