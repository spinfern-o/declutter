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
    var slotRects: [String: [Double]] = [:]  // slot -> [x, y, w, h] on the photo, as fractions; from the detected shelves
    @Relationship(deleteRule: .cascade, inverse: \Item.space) var items: [Item] = []
    var room: Room?  // the room this cabinet stands in; nil = a loose cabinet, as before rooms existed
    var spot: [Double]?  // where it stands in its room: [x, z, yaw, width, depth, height], room frame (see Room)

    init(name: String, photo: Data, zones: [String]) {
        self.name = name
        self.photo = photo
        self.zones = zones
    }

    /// Put a whole zone in a slot; the Plan list and the photo screen both move zones through here.
    func place(_ zone: String, in slot: String) {
        placement[zone] = slot
        try? modelContext?.save()
    }
}

extension Space {
    /// A cabinet from a detection reply: its items, and its detected shelves as slots when there are any.
    static func make(name: String, photo: Data, response: DetectResponse, in context: ModelContext) -> Space {
        let space = Space(name: name, photo: photo, zones: response.zones)
        context.insert(space)
        for found in response.items {
            space.items.append(Item(name: found.class.replacingOccurrences(of: "_", with: " "),
                                    className: found.class, zone: found.zone, confidence: found.confidence,
                                    cutout: Data(base64Encoded: found.cutout), box: found.box))
        }
        if let shelves = response.shelves, !shelves.isEmpty {  // otherwise the Plan screen asks for slots
            (space.slots, space.slotRects) = CabinetLayout.slots(fromShelves: shelves.map(\.box))
        }
        try? context.save()
        return space
    }
}
