import SwiftData
import SwiftUI

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
        space.slotRects = Dictionary(uniqueKeysWithValues: space.slotRects.compactMap { slot, rect in
            renamed[slot].map { ($0, rect) }  // a renamed slot keeps its outline; a deleted one loses it
        })
        for item in space.items {  // an item moved onto a renamed shelf stays on it; on a deleted one it rejoins its zone
            if let slot = item.slot { item.slot = renamed[slot] }
        }
        space.slots = names
        try? context.save()
        dismiss()
    }
}
