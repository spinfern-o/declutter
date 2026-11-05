import Foundation
import SwiftData

/// One photographed place (a cabinet for now; dorm rooms later).
@Model
final class Space {
    var name: String
    var createdAt = Date()
    @Attribute(.externalStorage) var photo: Data
    var zones: [String]  // from the server, in classes.csv order; also the choices for Move/Add
    var slots: [String] = []  // shelves/drawers, easiest to reach first
    var placement: [String: String] = [:]  // zone -> slot: rule results plus the user's overrides
    @Relationship(deleteRule: .cascade, inverse: \Item.space) var items: [Item] = []

    init(name: String, photo: Data, zones: [String]) {
        self.name = name
        self.photo = photo
        self.zones = zones
    }
}
