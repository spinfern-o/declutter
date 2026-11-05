import SwiftData

/// The room plan for one room, worked out from what's saved: which spot and shelf every item goes to.
struct RoomPlan {
    let cabinets: [Space]  // oldest first, so RoomOrganizer's cabinet indexes stay stable
    let items: [Item]  // every item detected in the room
    let placement: [[String: String]]  // per cabinet: the zone plan to save
    let shelves: [[String: String]]  // per cabinet: zone -> shelf for everything shown there
    private let cabinetOf: [PersistentIdentifier: Int]

    init(room: Room) {
        cabinets = room.spaces.sorted { ($0.createdAt, $0.persistentModelID) < ($1.createdAt, $1.persistentModelID) }
        items = cabinets.flatMap(\.items)
        let index = Dictionary(uniqueKeysWithValues: cabinets.enumerated().map { ($1.persistentModelID, $0) })
        var zones: [String] = []
        for zone in cabinets.flatMap(\.zones) where !zones.contains(zone) { zones.append(zone) }
        let result = RoomOrganizer.organize(
            items: items.map { (id: $0.persistentModelID, zone: $0.zone,
                                override: $0.destination.flatMap { index[$0.persistentModelID] }) },
            zones: zones,
            cabinets: cabinets.map { .init(slots: $0.slots, placement: RoomOrganizer.starting(room: $0.roomPlacement, own: $0.placement)) })
        placement = result.placement
        shelves = result.shelves
        cabinetOf = result.cabinet
    }

    func spot(of item: Item) -> Space? { cabinetOf[item.persistentModelID].map { cabinets[$0] } }

    func items(in space: Space) -> [Item] {
        items.filter { spot(of: $0)?.persistentModelID == space.persistentModelID }
    }

    func shelves(of space: Space) -> [String: String] {
        cabinets.firstIndex { $0.persistentModelID == space.persistentModelID }.map { shelves[$0] } ?? [:]
    }

    /// Saves the zone plan where it changed, and anything else pending (a moved item).
    func save(in context: ModelContext) {
        for (space, plan) in zip(cabinets, placement) where space.roomPlacement != plan { space.roomPlacement = plan }
        try? context.save()
    }
}
