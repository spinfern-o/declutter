import SwiftData
import SwiftUI

/// Mark where a messy spot (a cabinet) stands in a room. Stub until agent A's AR version lands: pick a
/// cabinet that isn't in a room yet, set its width, and it goes against the first wall, after the others.
struct SpotScanView: View {
    let room: Room
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Space.createdAt, order: .reverse) private var spaces: [Space]
    @State private var chosen: Space?
    @State private var width = 0.8

    var body: some View {
        NavigationStack {
            Form {
                Section("Cabinet") {
                    let loose = spaces.filter { $0.room == nil }
                    if loose.isEmpty {
                        Text("Photograph a cabinet in the Cabinets tab first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(loose) { space in
                        Button {
                            chosen = space
                        } label: {
                            LabeledContent(space.name) {
                                if chosen?.persistentModelID == space.persistentModelID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("Size") {
                    Stepper("Width \(width, format: .number.precision(.fractionLength(1))) m", value: $width, in: 0.2...3, step: 0.1)
                }
            }
            .navigationTitle("Add Messy Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(chosen == nil)
                }
            }
        }
    }

    private func add() {
        guard let chosen else { return }
        let depth = 0.45
        // against wall 0 (z = 0), facing into the room, to the right of the spots already there
        let onWall = room.spaces.compactMap(\.spot).filter { abs($0[1] - depth / 2) < 0.01 && $0[2] == 0 }
        let left = (onWall.map { $0[0] + $0[3] / 2 }.max() ?? 0) + 0.05
        chosen.room = room
        chosen.spot = [left + width / 2, depth / 2, 0, width, depth, 0.9]
        try? context.save()
        dismiss()
    }
}
