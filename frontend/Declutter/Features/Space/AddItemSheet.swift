import SwiftData
import SwiftUI

struct AddItemSheet: View {
    let space: Space
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var zone: String

    init(space: Space) {
        self.space = space
        _zone = State(initialValue: space.zones.first ?? "Misc")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Zone", selection: $zone) {
                    ForEach(space.zones, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        space.items.append(Item(name: trimmed, className: "manual", zone: zone))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
