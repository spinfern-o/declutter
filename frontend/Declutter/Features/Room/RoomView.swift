import RealityKit
import SwiftData
import SwiftUI

/// One room in 3D: its floor and walls, each messy spot as an open, tinted box at its spot with its shelves
/// and the items the room plan puts there, and furniture added from the marketplace at its real size.
/// Tapping a spot or a piece opens it; dragging one moves it across the floor; dragging elsewhere orbits.
struct RoomView: View {
    @Bindable var room: Room
    @Environment(\.modelContext) private var context
    @State private var addingSpot = false
    @State private var shopping = false
    @State private var opened: Space?
    @State private var removing: Space?  // a piece to delete once its sheet has closed
    @State private var models: [String: Entity] = [:]  // loaded once per object, cloned per item
    @State private var ratios: [PersistentIdentifier: Double] = [:]  // photo height / width per cabinet
    @State private var loadedVersion = -1  // ModelStore version the loaded models came from
    @State private var dragging = Dragging()  // a class, so updating it mid-drag doesn't rebuild the scene

    private final class Dragging {
        var entity: Entity?
        var grab: SIMD3<Float> = .zero  // finger point minus the cabinet's position, so it doesn't jump
    }

    var body: some View {
        // read here so any change re-runs `update` with fresh values
        let plan = RoomPlan(room: room)
        let _ = plan.items.map(\.slot)  // an item moved onto its own shelf in the cabinet screen shows here too
        let corners = room.corners, height = Float(room.wallHeight)
        let models = models, ratios = ratios

        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            root.name = "room"
            content.add(root)
            let light = DirectionalLight()
            light.look(at: .zero, from: [1, 4, 3], relativeTo: nil)
            content.add(light)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "room" }) else { return }
            build(root, plan: plan, corners: corners, height: height, models: models, ratios: ratios)
        }
        .realityViewCameraControls(.orbit)
        .highPriorityGesture(moveCabinet(plan))  // a drag on a cabinet moves it; elsewhere it orbits
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            if let i = Int(value.entity.name), plan.cabinets.indices.contains(i) { opened = plan.cabinets[i] }
        })
        .accessibilityElement()
        .accessibilityLabel(summary(plan))
        .accessibilityActions {
            ForEach(plan.cabinets) { space in
                Button("Open \(space.name)") { opened = space }
                if space.productURL != nil {
                    Button("Turn \(space.name)") {
                        if let spot = space.spot { space.spot = Furniture.turned(spot, in: room.corners); try? context.save() }
                    }
                }
                // the drag's VoiceOver counterpart: steps of 25 cm, as the room first appears (+x right, +z toward you)
                ForEach(Self.steps, id: \.name) { step in
                    Button("Move \(space.name) \(step.name)") {
                        if let spot = space.spot, spot.count == 6 { move(space, x: spot[0] + step.dx, z: spot[1] + step.dz) }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if room.spaces.isEmpty {
                Text("No messy spots yet. Add each cabinet or shelf you want to organize.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Add Furniture", systemImage: "cart") { shopping = true }
            Button("Add Messy Spot", systemImage: "plus") { addingSpot = true }
        }
        .sheet(isPresented: $addingSpot) { SpotScanView(room: room) }
        .sheet(isPresented: $shopping) { MarketView(room: room) }
        .sheet(item: $opened, onDismiss: removePending) { space in
            let remove = { removing = space; opened = nil }
            if space.productURL != nil && space.slots.isEmpty {  // a desk or a chair: nothing goes in it
                FurnitureSheet(space: space, room: room, remove: remove)
            } else {
                SpotSheet(space: space, room: room, models: models, ratio: ratios[space.persistentModelID] ?? 1, remove: remove)
            }
        }
        .onChange(of: plan.placement, initial: true) { plan.save(in: context) }
        .task(id: [room.spaces.count, ModelStore.shared.version]) { await load(plan) }
    }

    /// Drag a cabinet across the floor; on release its spot's x and z are saved, kept inside the room.
    private func moveCabinet(_ plan: RoomPlan) -> some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let cabinet = value.entity
                guard let root = cabinet.parent, Int(cabinet.name) != nil else { return }
                // the floor: the horizontal plane at the room root's height
                let floor = Transform(translation: [0, root.position(relativeTo: nil).y, 0]).matrix
                guard let world = value.unproject(value.location, from: .local, to: .scene, ontoPlane: floor) else { return }
                let point = root.convert(position: world, from: nil)
                if dragging.entity !== cabinet {
                    dragging.entity = cabinet
                    dragging.grab = point - cabinet.position
                }
                cabinet.position = [point.x - dragging.grab.x, 0, point.z - dragging.grab.z]
            }
            .onEnded { value in
                defer { dragging.entity = nil }
                guard dragging.entity === value.entity, let i = Int(value.entity.name), plan.cabinets.indices.contains(i) else { return }
                move(plan.cabinets[i], x: Double(value.entity.position.x), z: Double(value.entity.position.z))
            }
    }

    private static let steps: [(name: String, dx: Double, dz: Double)] =
        [("left", -0.25, 0), ("right", 0.25, 0), ("back", 0, -0.25), ("forward", 0, 0.25)]

    /// Saves a cabinet's new floor position, kept inside the room; yaw and size stay. The rebuild puts it there.
    private func move(_ space: Space, x: Double, z: Double) {
        guard var spot = space.spot, spot.count == 6 else { return }
        spot[0] = x
        spot[1] = z
        space.spot = RoomGeometry.clamp(spot, in: room.corners)
        try? context.save()
    }

    /// Deletes the piece the user removed, after its sheet is gone; items moved into it go back to the plan.
    private func removePending() {
        guard let space = removing else { return }
        removing = nil
        room.spaces.removeAll { $0 == space }
        context.delete(space)
        try? context.save()
    }

    private func load(_ plan: RoomPlan) async {
        for space in plan.cabinets {
            if let size = UIImage(data: space.photo)?.size, size.width > 0 {
                ratios[space.persistentModelID] = size.height / size.width
            }
        }
        var loaded = loadedVersion == ModelStore.shared.version ? models : [:]  // changed models: load them again
        loadedVersion = ModelStore.shared.version
        for object in Set(plan.items.compactMap({ ModelCatalog.object(name: $0.name, className: $0.className) }))
        where loaded[object] == nil {
            if let url = ModelCatalog.url(for: object), let entity = try? await Entity(contentsOf: url) { loaded[object] = entity }
        }
        models = loaded
    }

    // MARK: Building

    private func build(_ root: Entity, plan: RoomPlan, corners: [[Double]], height: Float,
                       models: [String: Entity], ratios: [PersistentIdentifier: Double]) {
        root.children.removeAll()
        let points = corners.filter { $0.count == 2 }.map { SIMD2<Float>(Float($0[0]), Float($0[1])) }
        guard points.count >= 3 else { return }
        // center the room on the origin and shrink it to about 1 m, the size the orbit camera frames
        let low = points.reduce(points[0]) { simd_min($0, $1) }, high = points.reduce(points[0]) { simd_max($0, $1) }
        let scale = 1.2 / max(high.x - low.x, high.y - low.y, height, 0.1)
        root.scale = .init(repeating: scale)
        root.position = [-(low.x + high.x) / 2 * scale, -height / 2 * scale, -(low.y + high.y) / 2 * scale]

        var outline = Path()
        outline.addLines(points.map { CGPoint(x: Double($0.x), y: Double($0.y)) })
        outline.closeSubpath()
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: 0.02)
        if let mesh = try? MeshResource(extruding: outline, extrusionOptions: options) {
            let floor = ModelEntity(mesh: mesh, materials: [Self.floor])
            floor.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])  // the path's y becomes the room's z
            floor.position.y = -0.011
            root.addChild(floor)
        }

        // which side is inside: the outline's winding (shoelace sign), x and z as a flat plane
        let next = Array(points.dropFirst()) + [points[0]]
        let area = zip(points, next).reduce(Float(0)) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
        for (a, b) in zip(points, next) {
            let d = b - a, length = simd_length(d)
            guard length > 0.01 else { continue }
            let inward = area > 0 ? SIMD2(-d.y, d.x) : SIMD2(d.y, -d.x)
            // one-sided, facing in: walls between the camera and the room show their back, which isn't drawn
            let wall = ModelEntity(mesh: .generatePlane(width: length, height: height), materials: [Self.wall])
            wall.orientation = simd_quatf(angle: atan2(inward.x, inward.y), axis: [0, 1, 0])
            wall.position = [(a.x + b.x) / 2, height / 2, (a.y + b.y) / 2]
            root.addChild(wall)
        }

        for (i, space) in plan.cabinets.enumerated() {
            guard let spot = space.spot, spot.count == 6 else { continue }
            let cabinet = Self.cabinet(space, plan: plan, size: [Float(spot[3]), Float(spot[5]), Float(spot[4])],
                                       ratio: ratios[space.persistentModelID] ?? 1, models: models)
            cabinet.name = "\(i)"  // the tap gesture finds the spot by this
            cabinet.position = [Float(spot[0]), 0, Float(spot[1])]
            cabinet.orientation = simd_quatf(angle: Float(spot[2]), axis: [0, 1, 0])  // yaw 0: front faces +z
            root.addChild(cabinet)
        }
    }

    /// An open box (front missing) standing on its own origin, front to +z, with the cabinet's shelves
    /// scaled to fill it and the items the room plan puts here on them. Marketplace furniture has its own
    /// tint, and a piece with no shelves (a desk) is one solid block.
    static func cabinet(_ space: Space, plan: RoomPlan, size: SIMD3<Float>, ratio: Double,
                                models: [String: Entity]) -> Entity {
        let (w, h, d) = (size.x, size.y, size.z), t: Float = 0.02
        let holder = Entity()
        let tint = space.productURL == nil ? Self.messy : Self.bought
        let solid = space.productURL != nil && space.slots.isEmpty
        var panels: [(SIMD3<Float>, SIMD3<Float>)] = [(size, [0, h / 2, 0])]
        if !solid {
            panels = [
                ([w, h, t], [0, h / 2, -d / 2 + t / 2]), ([t, h, d], [-w / 2 + t / 2, h / 2, 0]),
                ([t, h, d], [w / 2 - t / 2, h / 2, 0]), ([w, t, d], [0, h - t / 2, 0]), ([w, t, d], [0, t / 2, 0]),
            ]
        }
        for (panelSize, position) in panels {
            let panel = ModelEntity(mesh: .generateBox(size: panelSize), materials: [tint])
            panel.position = position
            holder.addChild(panel)
        }
        let label = ModelEntity(mesh: .generateText(space.name, extrusionDepth: 0.005, font: .systemFont(ofSize: 0.1)),
                                materials: [UnlitMaterial(color: .darkGray)])
        label.position = [-label.visualBounds(relativeTo: nil).extents.x / 2, h + 0.03, 0]
        holder.addChild(label)
        holder.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: [0, h / 2, 0])]))
        holder.components.set(InputTargetComponent())

        let rects = CabinetLayout.rects(slots: space.slots, saved: space.slotRects)
        guard !rects.isEmpty else { return holder }
        // the shelves' outline in the photo fills the box: photo fractions -> meters inside it
        let left = rects.values.map { $0[0] }.min()!, right = rects.values.map { $0[0] + $0[2] }.max()!
        let top = rects.values.map { $0[1] }.min()!, bottom = rects.values.map { $0[1] + $0[3] }.max()!
        let sx = (w - 2 * t) / Float(max(right - left, 1e-3)), sy = (h - 2 * t) / Float(max(bottom - top, 1e-3))
        func x(_ photoX: Double) -> Float { Float(photoX - left) * sx - w / 2 + t }
        func floorY(_ v: [Double]) -> Float { Float(bottom - v[1] - v[3]) * sy + t }

        for v in rects.values {
            let board = ModelEntity(mesh: .generateBox(width: Float(v[2]) * sx, height: 0.01, depth: d - t),
                                    materials: [Self.board])
            board.position = [x(v[0] + v[2] / 2), floorY(v) - 0.005, t / 2]
            holder.addChild(board)
        }

        let shelves = plan.shelves(of: space)
        // the shelf a user gave one item only counts in the cabinet it was found in: shelf names repeat across cabinets
        let placed: [(item: Item, slot: String)] = plan.items(in: space).compactMap { item in
            let own = item.space?.persistentModelID == space.persistentModelID ? item.slot : nil
            guard let slot = CabinetLayout.slot(override: own, zoneSlot: shelves[item.zone], slots: space.slots) else { return nil }
            return (item, slot)
        }
        let feet = CabinetLayout.footprints(
            items: placed.map { (id: $0.item.persistentModelID, slot: $0.slot, zone: $0.item.zone, name: $0.item.name, box: $0.item.box) },
            rects: rects, heightRatio: ratio)
        for (item, slot) in placed {
            guard let foot = feet[item.persistentModelID], let v = rects[slot] else { continue }
            let side = Float(foot.width) * sx, room = Float(v[3]) * sy * 0.9
            let visual = Self.visual(item, side: side, room: room, models: models)
            visual.position = [x(foot.midX), floorY(v), (Float(foot.midY / CabinetLayout.depth) - 0.5) * (d - t) + t / 2]
            holder.addChild(visual)
        }
        return holder
    }

    /// The item's model fitted into a side x room x side space, standing on its origin; a gray box if it has none.
    private static func visual(_ item: Item, side: Float, room: Float, models: [String: Entity]) -> Entity {
        let visual = Entity()
        if let object = ModelCatalog.object(name: item.name, className: item.className), let model = models[object] {
            // wrapped, so scaling it keeps the file's own unit scale (a cm model has 0.01 on its root)
            let wrapper = Entity()
            wrapper.addChild(model.clone(recursive: true))
            let bounds = wrapper.visualBounds(relativeTo: nil)
            let scale = min(side / max(bounds.extents.x, bounds.extents.z, 1e-4), room / max(bounds.extents.y, 1e-4))
            wrapper.scale = .init(repeating: scale)
            wrapper.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
            visual.addChild(wrapper)
        } else {
            let height = min(side, room)
            let box = ModelEntity(mesh: .generateBox(size: [side, height, side]), materials: [Self.placeholder])
            box.position.y = height / 2
            visual.addChild(box)
        }
        return visual
    }

    private static let floor = SimpleMaterial(color: UIColor(white: 0.85, alpha: 1), roughness: 0.9, isMetallic: false)
    private static let wall = SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.9, isMetallic: false)
    private static let messy = SimpleMaterial(color: .systemOrange, roughness: 0.7, isMetallic: false)
    private static let bought = SimpleMaterial(color: .systemTeal, roughness: 0.7, isMetallic: false)
    private static let board = SimpleMaterial(color: UIColor(red: 0.82, green: 0.70, blue: 0.55, alpha: 1), roughness: 0.8, isMetallic: false)
    private static let placeholder = SimpleMaterial(color: .systemGray3, roughness: 0.7, isMetallic: false)

    /// What VoiceOver reads: the room, then each spot with how many items the plan puts there.
    private func summary(_ plan: RoomPlan) -> String {
        let spots = plan.cabinets.map { space in
            let count = plan.items(in: space).count
            return "\(space.name): \(count == 1 ? "1 item" : "\(count) items")"
        }
        let messy = plan.cabinets.filter { $0.productURL == nil }.count  // furniture from the marketplace isn't a mess
        return (["\(room.name), \(messy == 1 ? "1 messy spot" : "\(messy) messy spots")"] + spots)
            .joined(separator: ". ")
    }
}
