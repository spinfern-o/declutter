import SwiftData
import SwiftUI

/// The rooms the user has outlined. New Room opens the scan; a room opens its own screen.
struct RoomsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Room.createdAt, order: .reverse) private var rooms: [Room]
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(rooms) { room in
                    NavigationLink(value: room) {
                        LabeledContent(room.name, value: room.spaces.count == 1 ? "1 spot" : "\(room.spaces.count) spots")
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(rooms[i]) }  // its cabinets stay, as loose cabinets
                    try? context.save()
                }
            }
            .overlay {
                if rooms.isEmpty {
                    ContentUnavailableView("No rooms yet", systemImage: "square.split.bottomrightquarter",
                                           description: Text("Outline your room, then mark where the messy spots are."))
                }
            }
            .navigationTitle("Rooms")
            .navigationDestination(for: Room.self) { RoomView(room: $0) }
            .toolbar {
                #if DEBUG
                Button("Sample Room", systemImage: "hammer") { _ = Room.sample(in: context) }
                #endif
                Button("New Room", systemImage: "plus") { scanning = true }
            }
            .fullScreenCover(isPresented: $scanning) { RoomScanView() }
        }
    }
}
