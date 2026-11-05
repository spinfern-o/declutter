import SwiftData
import SwiftUI

@main
struct DeclutterApp: App {
    init() {
        #if DEBUG
        Organizer.selfCheck()
        CabinetLayout.selfCheck()
        ModelCatalog.selfCheck()
        RoomOrganizer.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Rooms", systemImage: "square.split.bottomrightquarter") { RoomsView() }
                Tab("Cabinets", systemImage: "cabinet") { SpacesView() }
            }
        }
        .modelContainer(for: [Space.self, Room.self])
    }
}
