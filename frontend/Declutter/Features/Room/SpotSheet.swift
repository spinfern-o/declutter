import RealityKit
import SwiftData
import SwiftUI

/// One messy spot: the items the room plan puts here, then every item in the room by zone.
/// Picking an item from elsewhere moves it here; picking a moved item again sends it back to the plan.
struct SpotSheet: View {
    let space: Space
    let room: Room
    let models: [String: Entity]  // the room's loaded item models, so the 3D cabinet doesn't load them again
    let ratio: Double  // its photo's height / width
    let remove: () -> Void  // takes a piece from the marketplace out of the room
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var settingUp = false

    var body: some View {
        let plan = RoomPlan(room: room)
        let byZone = Dictionary(grouping: plan.items, by: \.zone)
        NavigationStack {
            VStack(spacing: 0) {
            CabinetPreview(space: space, plan: plan, models: models, ratio: ratio)
                .frame(height: 260)
            List {
                if space.productURL != nil { FurnitureActions(space: space, room: room, remove: remove) }
                Section("Here") {
                    let here = plan.items(in: space).byName
                    if space.slots.isEmpty {  // no shelves were detected in its photo: nothing can go here yet
                        Text("No shelves yet, so nothing can go here.").foregroundStyle(.secondary)
                        Button("Set Up Shelves", systemImage: "square.split.1x2") { settingUp = true }
                    } else if here.isEmpty {
                        Text("Nothing here yet. Pick items below to move them here.").foregroundStyle(.secondary)
                    }
                    ForEach(here) { row($0, plan: plan) }
                }
                ForEach(byZone.keys.sorted(), id: \.self) { zone in
                    Section {
                        ForEach(byZone[zone]!.byName) { row($0, plan: plan) }
                    } header: {
                        Label(zone, systemImage: Organizer.symbol(for: zone))
                    }
                }
            }
            }
            .navigationTitle(space.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $settingUp, onDismiss: { RoomPlan(room: room).save(in: context) }) { SlotsSheet(space: space) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: Item, plan: RoomPlan) -> some View {
        let spot = plan.spot(of: item)
        let here = spot?.persistentModelID == space.persistentModelID
        let moved = here && item.destination?.persistentModelID == space.persistentModelID
        let status = moved ? "Moved here" : here ? "Planned here" : spot.map { "In \($0.name)" } ?? "Not placed"
        let content = LabeledContent {
            HStack {
                Text(status)
                if here { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
        } label: {
            ItemRow(item: item)
        }
        if here && !moved {
            content  // the plan put it here: move it from the spot you want it in instead
                .accessibilityElement(children: .combine)
        } else {
            Button {
                item.destination = moved ? nil : space
                RoomPlan(room: room).save(in: context)  // the zone plan follows the new counts
            } label: {
                content
            }
            .foregroundStyle(.primary)
            .accessibilityElement(children: .combine)
            .accessibilityHint(moved ? "Sends it back to the plan" : "Moves it here")
            .accessibilityAddTraits(here ? .isSelected : [])
        }
    }
}

/// This cabinet alone in 3D, as the room plan organizes it: its shelves and the models of the items on them.
/// Read-only; drag to orbit, pinch to zoom.
private struct CabinetPreview: View {
    let space: Space
    let plan: RoomPlan
    let models: [String: Entity]
    let ratio: Double

    var body: some View {
        let spot = space.spot ?? [0, 0, 0, 0.8, 0.45, 0.9]  // a cabinet not placed yet gets the default size
        let size = SIMD3<Float>(Float(spot[3]), Float(spot[5]), Float(spot[4]))
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
            root.children.removeAll()
            let cabinet = RoomView.cabinet(space, plan: plan, size: size, ratio: ratio, models: models)
            let scale = 1 / max(size.x, size.y, 0.1)  // about 1 m across, the size the orbit camera frames
            cabinet.scale = .init(repeating: scale)
            cabinet.position.y = -size.y / 2 * scale
            root.addChild(cabinet)
        }
        .realityViewCameraControls(.orbit)
        .accessibilityElement()
        .accessibilityLabel("\(space.name) in 3D, \(plan.items(in: space).count) items")
    }
}
