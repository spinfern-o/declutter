import RealityKit
import SwiftData
import SwiftUI

/// The plan as a 3D cabinet: a board for each shelf (the detected shelves, in the photo's proportions)
/// with each item's model fitted onto its planned shelf. Dragging a model to another shelf moves its
/// whole zone, like on the Plan screen. Dragging empty space orbits the camera.
struct CabinetSceneView: View {
    @Bindable var space: Space
    @State private var heightRatio = 1.0  // photo height / width
    @State private var models: [String: Entity] = [:]  // loaded once per object, cloned per item
    @State private var dragging = Dragging()  // a class, so updating it mid-drag doesn't rebuild the scene
    @State private var moves = 0  // haptic trigger

    private final class Dragging {
        var entity: Entity?
        var start: SIMD3<Float> = .zero
        var grab: SIMD3<Float> = .zero  // finger point minus the model's position, so it doesn't jump
    }

    var body: some View {
        // read here so any change re-runs `update` with fresh values
        let rects = CabinetLayout.rects(slots: space.slots, saved: space.slotRects)
        let placement = space.placement
        let items = space.items.filter { $0.zone != Organizer.tossZone && placement[$0.zone] != nil }
        let models = models
        let ratio = heightRatio

        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            root.name = "cabinet"
            content.add(root)
            let light = DirectionalLight()
            light.look(at: .zero, from: [0.5, 1.5, 2], relativeTo: nil)
            content.add(light)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "cabinet" }) else { return }
            build(root, rects: rects, items: items, placement: placement, models: models, ratio: ratio)
        }
        .realityViewCameraControls(.orbit)
        .highPriorityGesture(drag(rects: rects, ratio: ratio))  // a drag on a model moves it; elsewhere it orbits
        .sensoryFeedback(.success, trigger: moves)
        .accessibilityElement()
        .accessibilityLabel(summary(rects: rects, items: items, placement: placement))
        .accessibilityActions {
            ForEach(Array(Set(items.map(\.zone))).sorted(), id: \.self) { zone in
                ForEach(space.slots.filter { $0 != placement[zone] }, id: \.self) { slot in
                    Button("Move \(zone) to \(slot)") { move(zone, to: slot) }
                }
            }
        }
        .navigationTitle("3D Cabinet")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ModelStore.shared.version) { await load() }  // again when the server's models change
    }

    private func load() async {
        if let size = UIImage(data: space.photo)?.size, size.width > 0 { heightRatio = size.height / size.width }
        var loaded: [String: Entity] = [:]
        for object in Set(space.items.compactMap({ ModelCatalog.object(name: $0.name, className: $0.className) })) {
            if let url = ModelCatalog.url(for: object), let entity = try? await Entity(contentsOf: url) { loaded[object] = entity }
        }
        models = loaded
    }

    // MARK: Building

    private func build(_ root: Entity, rects: [String: [Double]], items: [Item], placement: [String: String],
                       models: [String: Entity], ratio: Double) {
        root.children.removeAll()
        let r = Float(ratio), depth = Float(CabinetLayout.depth)
        // photo fractions -> scene meters: one photo width is 1 m, centered, y up
        func bottom(_ v: [Double]) -> Float { (0.5 - Float(v[1] + v[3])) * r }

        for (slot, v) in rects {
            let width = Float(v[2]), height = Float(v[3]) * r
            let left = Float(v[0]) - 0.5, floor = bottom(v)
            let board = ModelEntity(mesh: .generateBox(width: width, height: 0.015, depth: depth), materials: [Self.wood])
            board.position = [left + width / 2, floor - 0.0075, 0]
            let back = ModelEntity(mesh: .generateBox(width: width, height: height, depth: 0.005), materials: [Self.panel])
            back.position = [left + width / 2, floor + height / 2, -depth / 2]
            let label = Self.text(slot, size: 0.03)
            label.position = [left + 0.01, floor - 0.045, depth / 2 + 0.001]  // on the board's front edge
            root.addChild(board)
            root.addChild(back)
            root.addChild(label)
        }

        let feet = CabinetLayout.footprints(
            items: items.map { (id: $0.persistentModelID, zone: $0.zone, name: $0.name, box: $0.box) },
            placement: placement, rects: rects, heightRatio: ratio)
        for item in items {
            guard let foot = feet[item.persistentModelID], let slot = placement[item.zone], let v = rects[slot] else { continue }
            let side = Float(foot.width), room = Float(v[3]) * r * 0.95  // leave a gap under the next shelf

            let visual: Entity
            if let object = ModelCatalog.object(name: item.name, className: item.className), let model = models[object] {
                // wrapped, so scaling it keeps the file's own unit scale (a cm model has 0.01 on its root)
                visual = Entity()
                visual.addChild(model.clone(recursive: true))
                let bounds = visual.visualBounds(relativeTo: nil)
                let scale = min(side / max(bounds.extents.x, bounds.extents.z, 1e-4), room / max(bounds.extents.y, 1e-4))
                visual.scale = .init(repeating: scale)
                // your model can be any scale with its origin anywhere: center it and stand it on the board
                visual.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
            } else {
                visual = Self.placeholder(item.name, side: side, height: min(side, room))
            }

            let holder = Entity()
            holder.name = item.zone
            holder.addChild(visual)
            holder.position = [Float(foot.midX) - 0.5, bottom(v), -depth / 2 + Float(foot.midY)]
            let bounds = holder.visualBounds(relativeTo: holder)
            holder.components.set(CollisionComponent(shapes: [.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)]))
            holder.components.set(InputTargetComponent())
            root.addChild(holder)
        }
    }

    /// A gray box with the item's name on its front, for items with no model yet.
    private static func placeholder(_ name: String, side: Float, height: Float) -> Entity {
        let box = ModelEntity(mesh: .generateBox(width: side, height: height, depth: side, cornerRadius: side * 0.08),
                              materials: [SimpleMaterial(color: .systemGray3, roughness: 0.7, isMetallic: false)])
        box.position.y = height / 2
        let label = text(name, size: 0.02)
        let extents = label.visualBounds(relativeTo: nil).extents
        let fit = min(1, side * 0.9 / max(extents.x, 1e-4))
        label.scale = .init(repeating: fit)
        label.position = [-extents.x * fit / 2, height / 2 - extents.y * fit / 2, side / 2 + 0.001]
        let entity = Entity()
        entity.addChild(box)
        entity.addChild(label)
        return entity
    }

    private static func text(_ string: String, size: CGFloat) -> ModelEntity {
        ModelEntity(mesh: .generateText(string, extrusionDepth: 0.001, font: .systemFont(ofSize: size)),
                    materials: [UnlitMaterial(color: .darkGray)])
    }

    private static let wood = SimpleMaterial(color: UIColor(red: 0.82, green: 0.70, blue: 0.55, alpha: 1), roughness: 0.8, isMetallic: false)
    private static let panel = SimpleMaterial(color: UIColor(white: 0.93, alpha: 1), roughness: 0.9, isMetallic: false)

    // MARK: Moving

    private func drag(rects: [String: [Double]], ratio: Double) -> some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let holder = value.entity
                // follow the finger on the plane facing the camera through the model (its normal is the y axis, turned to z)
                let plane = Transform(rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
                                      translation: [0, 0, holder.position.z]).matrix
                guard let point = value.unproject(value.location, from: .local, to: .scene, ontoPlane: plane) else { return }
                if dragging.entity !== holder {
                    dragging.entity = holder
                    dragging.start = holder.position
                    dragging.grab = point - holder.position
                }
                holder.position = [point.x - dragging.grab.x, point.y - dragging.grab.y, dragging.start.z]
            }
            .onEnded { value in
                let holder = value.entity
                defer { dragging.entity = nil }
                // the front-view spot just above where it was let go, in layout space (photo widths, y down)
                let drop = CGPoint(x: Double(holder.position.x) + 0.5, y: 0.5 * ratio - Double(holder.position.y) - 0.02)
                if let slot = CabinetLayout.slot(at: drop, in: rects, heightRatio: ratio), slot != space.placement[holder.name] {
                    move(holder.name, to: slot)  // the rebuild puts it on its new shelf
                } else {  // off every shelf, or back on its own: spring back
                    var home = holder.transform
                    home.translation = dragging.start
                    holder.move(to: home, relativeTo: holder.parent, duration: 0.25)
                }
            }
    }

    private func move(_ zone: String, to slot: String) {
        space.place(zone, in: slot)
        moves += 1
    }

    /// What VoiceOver reads: each shelf from top to bottom with what's on it.
    private func summary(rects: [String: [Double]], items: [Item], placement: [String: String]) -> String {
        rects.sorted { $0.value[1] < $1.value[1] }.map { slot, _ in
            let names = items.filter { placement[$0.zone] == slot }.byName.map(\.name)
            return "\(slot): \(names.isEmpty ? "empty" : names.joined(separator: ", "))"
        }.joined(separator: ". ")
    }
}
