import SwiftData
import SwiftUI

/// Outline a new room. Stub until agent A's ARKit corner-tapping lands: a typed rectangle, which stays
/// as the fallback where AR isn't available (the Simulator).
struct RoomScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My Room"
    @State private var width = 4.0
    @State private var length = 3.5

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Stepper("Width \(width, format: .number.precision(.fractionLength(1))) m", value: $width, in: 1...15, step: 0.1)
                Stepper("Length \(length, format: .number.precision(.fractionLength(1))) m", value: $length, in: 1...15, step: 0.1)
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let corners = [[0, 0], [width, 0], [width, length], [0, length]]  // wall 0 along +x, room toward +z
        context.insert(Room(name: name.trimmingCharacters(in: .whitespaces), corners: corners))
        try? context.save()
        dismiss()
    }
}
