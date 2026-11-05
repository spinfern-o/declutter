import SwiftData
import SwiftUI

@main
struct DeclutterApp: App {
    init() {
        #if DEBUG
        Organizer.selfCheck()
        CabinetLayout.selfCheck()
        ModelCatalog.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SpacesView()
        }
        .modelContainer(for: Space.self)
    }
}
