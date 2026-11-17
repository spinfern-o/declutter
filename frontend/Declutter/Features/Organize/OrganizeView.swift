import SwiftData
import SwiftUI

/// The placement plan: what to toss, then which zone goes in which shelf or drawer.
struct OrganizeView: View {
    @Bindable var space: Space
    @Environment(\.modelContext) private var context
    @State private var editingSlots = false
    @State private var moves = 0  // haptic trigger

    private var counts: [String: Int] {
        Dictionary(space.items.map { ($0.zone, 1) }, uniquingKeysWith: +)
    }

    var body: some View {
        List {
            let toss = space.items.filter { $0.zone == Organizer.tossZone }
            if !toss.isEmpty {
                Section {
                    ForEach(toss.byName) { ItemRow(item: $0) }
                } header: {
                    Label {
                        Text("Toss First")
                    } icon: {
                        Image(systemName: Organizer.symbol(for: Organizer.tossZone)).foregroundStyle(.red)
                    }
                }
            }
            ForEach(space.slots, id: \.self) { slot in
                Section(slot) {
                    let zones = zones(in: slot)
                    // List swallows row-level drops; the ForEach's own drop API is what List honors.
                    // An empty slot gets one "" placeholder row so it can still take a drop.
                    ForEach(zones.isEmpty ? [""] : zones, id: \.self) { zone in
                        if zone.isEmpty {
                            Text("Free space").foregroundStyle(.secondary)
                        } else {
                            zoneRow(zone, in: slot)
                            ForEach(space.items.filter { $0.zone == zone && space.shelf(of: $0) == slot }.byName) { item in
                                ItemRow(item: item).padding(.leading)
                            }
                        }
                    }
                    .dropDestination(for: String.self) { dropped, _ in drop(dropped, in: slot) }
                    // items dragged here one by one in the 3D cabinet, away from their zone's shelf
                    ForEach(movedItems(in: slot)) { item in
                        ItemRow(item: item)
                            .swipeActions {
                                Button("Back with \(item.zone)", systemImage: "arrow.uturn.backward") { sendBack(item) }
                            }
                            .accessibilityAction(named: "Back with \(item.zone)") { sendBack(item) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if space.slots.isEmpty {
                ContentUnavailableView {
                    Label("No Slots Yet", systemImage: "cabinet")
                } description: {
                    Text("Tell Declutter which shelves and drawers this cabinet has.")
                } actions: {
                    Button("Set Up Cabinet") { editingSlots = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Plan")
        .toolbar {
            Menu {
                Button("Edit Slots", systemImage: "square.split.1x2") { editingSlots = true }
                Button("Re-sort", systemImage: "arrow.triangle.2.circlepath") {
                    space.placement = [:]
                    for item in space.items { item.slot = nil }  // items moved one by one go back with their zone
                    space.replan()
                    try? context.save()
                }
            } label: {
                Label("Options", systemImage: "ellipsis")
            }
            .disabled(space.slots.isEmpty)
        }
        .sheet(isPresented: $editingSlots) { SlotsSheet(space: space) }
        .sensoryFeedback(.success, trigger: moves)
        .onAppear {
            if space.slots.isEmpty { editingSlots = true }
            space.replan()
        }
        .onChange(of: space.slots) { space.replan() }
    }

    private func zoneRow(_ zone: String, in slot: String) -> some View {
        let count = space.items.filter { $0.zone == zone && space.shelf(of: $0) == slot }.count  // not the ones moved away
        let countText = count == 1 ? "1 item" : "\(count) items"
        let others = space.slots.filter { $0 != slot }
        return LabeledContent {
            Text(countText)
        } label: {
            Label(zone, systemImage: Organizer.symbol(for: zone))
                .symbolRenderingMode(.hierarchical)
                .font(.headline)
        }
        .draggable(zone)
        .contextMenu {
            Menu("Move to Slot", systemImage: "arrow.right") {
                ForEach(others, id: \.self) { target in
                    Button(target) { place(zone, in: target) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(zone), \(countText), \(slot)")
        .accessibilityActions {
            ForEach(others, id: \.self) { target in
                Button("Move to \(target)") { place(zone, in: target) }
            }
        }
    }

    /// Zones placed in this slot, biggest first.
    private func zones(in slot: String) -> [String] {
        space.placement
            .filter { $0.value == slot && counts[$0.key, default: 0] > 0 }
            .keys
            .sorted { (counts[$1]!, $0) < (counts[$0]!, $1) }
    }

    private func drop(_ dropped: [String], in slot: String) {
        guard let zone = dropped.first, counts[zone] != nil, zone != Organizer.tossZone else { return }
        place(zone, in: slot)
    }

    private func place(_ zone: String, in slot: String) {
        space.place(zone, in: slot)
        moves += 1
    }

    /// Items the user put on this shelf one by one while their zone sits on another.
    private func movedItems(in slot: String) -> [Item] {
        space.items
            .filter { $0.zone != Organizer.tossZone && space.placement[$0.zone] != slot && space.shelf(of: $0) == slot }
            .byName
    }

    private func sendBack(_ item: Item) {
        item.slot = nil
        try? context.save()
        moves += 1
    }
}
