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
                            ForEach(space.items.filter { $0.zone == zone }.byName) { item in
                                ItemRow(item: item).padding(.leading)
                            }
                        }
                    }
                    .dropDestination(for: String.self) { dropped, _ in drop(dropped, in: slot) }
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
                    replan()
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
            replan()
        }
        .onChange(of: space.slots) { replan() }
    }

    private func zoneRow(_ zone: String, in slot: String) -> some View {
        let count = counts[zone, default: 0]
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
        space.placement[zone] = slot
        try? context.save()
        moves += 1
    }

    /// Place any zone that has no slot yet; leaves the user's choices alone.
    private func replan() {
        let plan = Organizer.plan(counts: counts, zones: space.zones, slots: space.slots, current: space.placement)
        if plan != space.placement {
            space.placement = plan
            try? context.save()
        }
    }
}
