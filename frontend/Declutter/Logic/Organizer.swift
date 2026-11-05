import Foundation

/// Rule-based placement: which zone goes in which shelf or drawer. Pure functions, so they can be self-checked.
enum Organizer {
    static let tossZone = "Toss / recycle"  // must match the zone name in backend/train/classes.csv

    /// zone -> slot. `slots` are ordered easiest to reach first; `current` holds earlier placements and user overrides.
    static func plan(counts: [String: Int], zones: [String], slots: [String], current: [String: String]) -> [String: String] {
        guard !slots.isEmpty else { return [:] }
        // keep overrides that still point at a slot that exists
        var placement = current.filter { slots.contains($0.value) && counts[$0.key, default: 0] > 0 }
        var load = Dictionary(uniqueKeysWithValues: slots.map { ($0, 0) })
        for (zone, slot) in placement { load[slot, default: 0] += counts[zone, default: 0] }

        // shortcut: item count stands in for frequency of use; replace once users can mark favorite/daily items
        let known = zones + counts.keys.filter { !zones.contains($0) }.sorted()
        let todo = known.enumerated()
            .filter { $0.element != tossZone && counts[$0.element, default: 0] > 0 && placement[$0.element] == nil }
            .sorted { a, b in
                let (ca, cb) = (counts[a.element]!, counts[b.element]!)
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map(\.element)

        for zone in todo {
            let free = slots.first { slot in !placement.values.contains(slot) }
            // overflow: least-full slot; ties go to the less reachable one so prime spots stay clear
            let slot = free ?? slots.reversed().min { load[$0]! < load[$1]! }!
            placement[zone] = slot
            load[slot]! += counts[zone]!
        }
        return placement
    }

    static func symbol(for zone: String) -> String {
        [
            tossZone: "trash", "Paper": "doc.text", "Tech": "cable.connector", "Office": "pencil.and.ruler",
            "Household": "wrench.and.screwdriver", "Toiletries": "drop",
        ][zone] ?? "square.grid.2x2"
    }

    static func selfCheck() {
        let zones = [tossZone, "Paper", "Tech", "Misc"]
        let three = ["Top", "Middle", "Bottom"]

        var p = plan(counts: [tossZone: 5, "Paper": 1, "Tech": 3, "Misc": 2], zones: zones, slots: three, current: [:])
        assert(p[tossZone] == nil, "toss items are never placed")
        assert(p["Tech"] == "Top" && p["Misc"] == "Middle" && p["Paper"] == "Bottom", "biggest zone gets the easiest slot")

        p = plan(counts: ["Paper": 1, "Tech": 3, "Misc": 2], zones: zones, slots: ["Top", "Bottom"], current: [:])
        assert(p["Paper"] == "Bottom", "overflow goes to the least-full slot")

        p = plan(counts: ["Paper": 1, "Tech": 3], zones: zones, slots: three, current: ["Paper": "Top"])
        assert(p["Paper"] == "Top" && p["Tech"] == "Middle", "user overrides survive")

        p = plan(counts: ["Tech": 3], zones: zones, slots: three, current: ["Tech": "Gone"])
        assert(p["Tech"] == "Top", "a zone on a deleted slot is placed again")
    }
}
