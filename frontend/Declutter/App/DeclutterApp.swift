import SwiftData
import SwiftUI

@main
struct DeclutterApp: App {
    init() {
        #if DEBUG
        Organizer.selfCheck()
        CabinetLayout.selfCheck()
        ModelCatalog.selfCheck()
        ModelStore.selfCheck()
        RoomGeometry.selfCheck()
        RoomOrganizer.selfCheck()
        Furniture.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Rooms", systemImage: "square.split.bottomrightquarter") { RoomsView() }
                Tab("Cabinets", systemImage: "cabinet") { SpacesView() }
            }
            .task { await ModelStore.shared.sync() }  // new or changed 3D models from the server
        }
        .modelContainer(for: [Space.self, Room.self])
    }
}
