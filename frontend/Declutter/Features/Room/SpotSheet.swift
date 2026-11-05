import SwiftData
import SwiftUI

/// One messy spot: the items the room plan puts here, then every item in the room by zone.
/// Picking an item from elsewhere moves it here; picking a moved item again sends it back to the plan.
struct SpotSheet: View {
    let space: Space
    let room: Room
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var settingUp = false

    var body: some View {
        let plan = RoomPlan(room: room)
        let byZone = Dictionary(grouping: plan.items, by: \.zone)
        NavigationStack {
            List {
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
