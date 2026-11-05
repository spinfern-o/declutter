import Foundation

/// Organizes every item in a room across all of its cabinets' shelves, with `Organizer`'s rules.
/// Cabinets are addressed by their index in the order the caller gives (keep it stable: oldest first).
/// Pure functions, so they can be self-checked.
enum RoomOrganizer {
    struct Cabinet {
        var slots: [String]  // its shelves, easiest to reach first
        var placement: [String: String]  // its saved part of the room plan: zone -> shelf
    }

    struct Result<ID: Hashable> {
        var placement: [[String: String]]  // per cabinet, the room plan's zones -> shelf; save this
        var shelves: [[String: String]]  // per cabinet, every zone shown there (plan + moved items) -> shelf
        var cabinet: [ID: Int]  // where each item ends up; missing = nowhere (toss, or no shelves in the room)
    }

    /// Every (cabinet, shelf) pair, rank 0 of every cabinet first, then rank 1, and so on.
    static func reachOrder(_ cabinets: [[String]]) -> [(cabinet: Int, shelf: String)] {
        (0..<(cabinets.map(\.count).max() ?? 0)).flatMap { rank in
            cabinets.indices.compactMap { c in rank < cabinets[c].count ? (c, cabinets[c][rank]) : nil }
        }
    }

    /// `override` is the cabinet index the user moved the item to; it wins over the zone plan.
    static func organize<ID: Hashable>(items: [(id: ID, zone: String, override: Int?)], zones: [String],
                                       cabinets: [Cabinet]) -> Result<ID> {
        func valid(_ c: Int?) -> Int? { c.flatMap { cabinets.indices.contains($0) ? $0 : nil } }
        // Organizer plans over plain slot names, so each (cabinet, shelf) becomes one name for the room
        let order = reachOrder(cabinets.map(\.slots))
        func key(_ c: Int, _ shelf: String) -> String { "\(c)\n\(shelf)" }
        let slotOf = Dictionary(order.map { (key($0.cabinet, $0.shelf), $0) }, uniquingKeysWith: { a, _ in a })
        var current: [String: String] = [:]
        for (c, cabinet) in cabinets.enumerated() {
            for (zone, shelf) in cabinet.placement where current[zone] == nil { current[zone] = key(c, shelf) }
        }

        let counts = Dictionary(items.filter { valid($0.override) == nil }.map { ($0.zone, 1) }, uniquingKeysWith: +)
        let plan = Organizer.plan(counts: counts, zones: zones, slots: order.map { key($0.cabinet, $0.shelf) }, current: current)
        var placement = cabinets.map { _ in [String: String]() }
        for (zone, k) in plan { if let s = slotOf[k] { placement[s.cabinet][zone] = s.shelf } }

        var cabinetOf: [ID: Int] = [:]
        for item in items {
            cabinetOf[item.id] = valid(item.override) ?? plan[item.zone].flatMap { slotOf[$0]?.cabinet }
        }
        // a moved item's zone may have no shelf in its new cabinet: plan the cabinet again around the room plan
        let shelves = cabinets.indices.map { c in
            let here = Dictionary(items.filter { cabinetOf[$0.id] == c }.map { ($0.zone, 1) }, uniquingKeysWith: +)
            return Organizer.plan(counts: here, zones: zones, slots: cabinets[c].slots, current: placement[c])
        }
        return Result(placement: placement, shelves: shelves, cabinet: cabinetOf)
    }

    static func selfCheck() {
        let order = reachOrder([["A mid", "A top"], ["B only"], ["C mid", "C top", "C low"]])
        assert(order.map { "\($0.cabinet) \($0.shelf)" } == ["0 A mid", "1 B only", "2 C mid", "0 A top", "2 C top", "2 C low"],
               "reach order interleaves the cabinets' own ranks")

        let two = [Cabinet(slots: ["A mid", "A top"], placement: [:]), Cabinet(slots: ["B only"], placement: [:])]
        func items(_ counts: [(String, Int)], override: [Int: Int] = [:]) -> [(id: Int, zone: String, override: Int?)] {
            counts.flatMap { zone, n in (0..<n).map { (zone, $0) } }.enumerated()
                .map { (id: $0.offset, zone: $0.element.0, override: override[$0.offset]) }
        }
        let zones = [Organizer.tossZone, "Paper", "Tech", "Misc", "Office"]
        let mess = items([("Tech", 3), ("Paper", 2), ("Misc", 1), (Organizer.tossZone, 2)])  // ids 0-2 Tech, 3-4 Paper, 5 Misc, 6-7 toss

        var r = organize(items: mess, zones: zones, cabinets: two)
        assert(r.placement.count == 2 && r.placement[0] == ["Tech": "A mid", "Misc": "A top"] && r.placement[1] == ["Paper": "B only"],
               "biggest zone gets the easiest shelf in the room")
        assert(r.cabinet[0] == 0 && r.cabinet[3] == 1 && r.cabinet[5] == 0, "items follow their zone to its cabinet")
        assert(r.cabinet[6] == nil && r.cabinet[7] == nil, "toss items are never placed")

        r = organize(items: mess + items([("Office", 1)]).map { (id: 100, zone: $0.zone, override: nil) }, zones: zones, cabinets: two)
        assert(r.placement[0]["Office"] == "A top", "overflow goes to the least-full shelf in the room")

        var kept = two
        kept[0].placement = ["Paper": "A mid", "Gone": "A mid"]
        kept[1].placement = ["Misc": "Removed shelf"]
        r = organize(items: mess, zones: zones, cabinets: kept)
        assert(r.placement[0] == ["Paper": "A mid", "Misc": "A top"] && r.placement[1] == ["Tech": "B only"],
               "saved placements survive; ones on missing shelves or empty zones are placed again")

        // ids 0-3 Tech, 4-5 Paper, 6 Misc; Tech 1 moved to cabinet 1, Misc to a cabinet that isn't there
        r = organize(items: items([("Tech", 4), ("Paper", 2), ("Misc", 1)], override: [1: 1, 6: 9]), zones: zones, cabinets: two)
        assert(r.cabinet[1] == 1 && r.cabinet[0] == 0 && r.cabinet[2] == 0, "a moved item goes where the user put it")
        assert(r.placement[1]["Tech"] == nil && r.shelves[1]["Tech"] == "B only", "a moved item gets a shelf without moving its zone")
        assert(r.cabinet[6] == 0, "a move to a cabinet outside the room is ignored")

        r = organize(items: mess, zones: zones, cabinets: [Cabinet(slots: [], placement: [:])])
        assert(r.cabinet.isEmpty && r.placement == [[:]], "a room with no shelves places nothing")
    }
}
