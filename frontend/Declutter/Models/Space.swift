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
    var roomPlacement: [String: String] = [:]  // zone -> shelf: this cabinet's part of its room's plan (RoomOrganizer)
    @Relationship(deleteRule: .nullify, inverse: \Item.destination) var movedHere: [Item] = []  // items moved here from elsewhere in the room
    var productURL: String?  // its page at the store, for a piece added from the marketplace; nil = a photographed cabinet
    var productStore: String?  // the store's name, for the link's label

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

    /// Put one item on a shelf, apart from its zone; the 3D cabinet moves items through here.
    func place(_ item: Item, in slot: String) {
        item.slot = CabinetLayout.ownSlot(droppedOn: slot, zoneSlot: placement[item.zone])
        try? modelContext?.save()
    }

    /// The shelf an item sits on in this cabinet's own plan; nil when its zone has none yet.
    func shelf(of item: Item) -> String? {
        CabinetLayout.slot(override: item.slot, zoneSlot: placement[item.zone], slots: slots)
    }

    /// Place any zone that has no slot yet; leaves the user's choices alone.
    func replan() {
        let counts = Dictionary(items.map { ($0.zone, 1) }, uniquingKeysWith: +)
        let plan = Organizer.plan(counts: counts, zones: zones, slots: slots, current: placement)
        if plan != placement {
            placement = plan
            try? modelContext?.save()
        }
    }
}

extension Space {
    /// A piece from the marketplace, standing in the middle of the room at its real size. It has no photo and
    /// no items of its own; a storage piece gets shelves, so the room plan and the user can put items in it.
    static func furniture(_ product: Product, in room: Room, context: ModelContext) -> Space {
        let space = Space(name: product.name, photo: Data(), zones: [])
        context.insert(space)
        space.productURL = product.url
        space.productStore = product.store
        if product.kind == "storage" {
            (space.slots, space.slotRects) = CabinetLayout.slots(fromShelves: Furniture.shelves(product.levels ?? 1))
        }
        space.room = room
        space.spot = Furniture.spot(size: Furniture.meters(product.size_in), in: room.corners)
        try? context.save()
        return space
    }

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
