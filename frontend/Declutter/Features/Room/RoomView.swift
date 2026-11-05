import SwiftData
import SwiftUI

/// One room. Stub until agent B's 3D room lands: its messy spots as a list, and Add Messy Spot.
struct RoomView: View {
    @Bindable var room: Room
    @State private var addingSpot = false

    var body: some View {
        List {
            ForEach(room.spaces.sorted { $0.createdAt < $1.createdAt }) { space in
                NavigationLink(value: space) {
                    LabeledContent(space.name, value: "\(space.items.count) items")
                }
            }
        }
        .overlay {
            if room.spaces.isEmpty {
                ContentUnavailableView("No messy spots yet", systemImage: "cabinet",
                                       description: Text("Add each cabinet or shelf you want to organize."))
            }
        }
        .navigationTitle(room.name)
        .navigationDestination(for: Space.self) { SpaceView(space: $0) }
        .toolbar {
            Button("Add Messy Spot", systemImage: "plus") { addingSpot = true }
        }
        .sheet(isPresented: $addingSpot) { SpotScanView(room: room) }
    }
}
