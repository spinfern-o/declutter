import SwiftData
import SwiftUI

/// What you can do with a piece from the marketplace: see it at its store, turn it, take it out of the room.
struct FurnitureActions: View {
    let space: Space
    let room: Room
    let remove: () -> Void  // the room screen closes the sheet first, then deletes the piece
    @Environment(\.modelContext) private var context

    var body: some View {
        Section {
            if let link = space.productURL, link.hasPrefix("https://"), let url = URL(string: link) {
                Link("View at \(space.productStore ?? "the Store")", destination: url)
            }
            Button("Turn a Quarter", systemImage: "rotate.right") {
                guard let spot = space.spot else { return }
                space.spot = Furniture.turned(spot, in: room.corners)
                try? context.save()
            }
            Button("Remove from Room", systemImage: "trash", role: .destructive, action: remove)
        }
    }
}

/// A placed piece that holds nothing (a desk, a chair): its size and what you can do with it.
struct FurnitureSheet: View {
    let space: Space
    let room: Room
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let spot = space.spot, spot.count == 6 {
                    LabeledContent("Size", value: Furniture.label(sizeInches: [spot[3], spot[4], spot[5]].map { $0 / Furniture.inch }))
                }
                FurnitureActions(space: space, room: room, remove: remove)
            }
            .navigationTitle(space.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
