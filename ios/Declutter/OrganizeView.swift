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

/// Edit the cabinet's shelves and drawers, easiest to reach first.
struct SlotsSheet: View {
    let space: Space
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var slots: [Slot]

    private struct Slot: Identifiable {
        let id = UUID()
        var name: String
        let original: String?  // lets a rename keep the zones that were placed there
    }

    private static let presets: [(title: String, slots: [String])] = [
        ("3 Shelves", ["Middle shelf", "Top shelf", "Bottom shelf"]),
        ("2 Drawers + 2 Shelves", ["Top drawer", "Bottom drawer", "Upper shelf", "Lower shelf"]),
        ("4 Drawers", ["Top drawer", "Second drawer", "Third drawer", "Bottom drawer"]),
    ]

    init(space: Space) {
        self.space = space
        _slots = State(initialValue: space.slots.map { Slot(name: $0, original: $0) })
    }

    private var names: [String] { slots.map { $0.name.trimmingCharacters(in: .whitespaces) } }
    private var valid: Bool { !names.isEmpty && !names.contains("") && Set(names).count == names.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($slots) { $slot in
                        TextField("Name", text: $slot.name)
                    }
                    .onDelete { slots.remove(atOffsets: $0) }
                    .onMove { slots.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Slot", systemImage: "plus") {
                        slots.append(Slot(name: "Slot \(slots.count + 1)", original: nil))
                    }
                } header: {
                    Text("Easiest to reach first")
                } footer: {
                    Text("Drag to reorder. The biggest groups go in the easiest spots. Names must be unique.")
                }
                Section("Quick Start") {
                    ForEach(Self.presets, id: \.title) { preset in
                        Button(preset.title) {
                            slots = preset.slots.map { Slot(name: $0, original: nil) }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Cabinet Slots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(!valid)
                }
            }
        }
    }

    private func save() {
        var renamed: [String: String] = [:]
        for (slot, name) in zip(slots, names) {
            if let original = slot.original { renamed[original] = name }
        }
        space.placement = space.placement.compactMapValues { renamed[$0] }  // zones on deleted slots get re-placed
        space.slots = names
        try? context.save()
        dismiss()
    }
}
