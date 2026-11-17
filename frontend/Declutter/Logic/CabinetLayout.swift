import CoreGraphics

/// Geometry for the 3D cabinet. Item boxes and shelf rectangles are [x, y, w, h] fractions of the photo's
/// width and height; layout works in "photo widths" (x and y both divided by the width), and the 3D scene
/// draws one photo width as 1 m, so the cabinet keeps the photo's proportions. Pure functions, self-checked.
enum CabinetLayout {
    static let defaultSide = 0.12  // footprint for items with no box: manual items and cabinets saved earlier
    static let depth = 0.4  // the photo has no depth, so every shelf gets the same

    /// A saved [x, y, w, h] fraction rectangle, in layout space. `heightRatio` is photo height / width.
    static func rect(_ v: [Double], heightRatio: Double) -> CGRect {
        CGRect(x: v[0], y: v[1] * heightRatio, width: v[2], height: v[3] * heightRatio)
    }

    /// An item's footprint: about the size it was in the photo, clamped so tiny items stay visible.
    static func side(for box: [Double]?, heightRatio: Double) -> Double {
        guard let box, box.count == 4 else { return defaultSide }
        return min(max((box[2] + box[3] * heightRatio) / 2, 0.05), 0.25)
    }

    /// Squares laid out in rows inside `rect`, in the order given, all shrunk by one shared factor
    /// (never grown) until they fit. Squares sit on the bottom of their row.
    // shortcut: row packing only, no rotation or gap-filling; upgrade if slots look crowded
    static func pack<ID: Hashable>(_ items: [(id: ID, side: Double)], in rect: CGRect) -> [ID: CGRect] {
        func rows(_ scale: Double) -> [[(id: ID, side: Double)]] {
            var rows: [[(id: ID, side: Double)]] = [[]]
            var x = 0.0
            for item in items {
                let side = item.side * scale
                if x + side > rect.width + 1e-9, !rows[rows.count - 1].isEmpty {
                    rows.append([])
                    x = 0
                }
                rows[rows.count - 1].append((id: item.id, side: side))
                x += side
            }
            return rows
        }
        func fits(_ scale: Double) -> Bool {
            let laid = rows(scale)
            return laid.allSatisfy { $0.reduce(0) { $0 + $1.side } <= rect.width + 1e-9 }
                && laid.reduce(0) { $0 + ($1.map(\.side).max() ?? 0) } <= rect.height + 1e-9
        }

        var scale = 1.0
        if !fits(scale) {
            var (low, high) = (0.0, 1.0)
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if fits(mid) { low = mid } else { high = mid }
            }
            scale = low
        }

        // center the block vertically and each row horizontally
        let laid = rows(scale)
        let heights = laid.map { $0.map(\.side).max() ?? 0 }
        var y = rect.minY + (rect.height - heights.reduce(0, +)) / 2
        var result: [ID: CGRect] = [:]
        for (row, height) in zip(laid, heights) {
            var x = rect.minX + (rect.width - row.reduce(0) { $0 + $1.side }) / 2
            for item in row {
                result[item.id] = CGRect(x: x, y: y + height - item.side, width: item.side, height: item.side)
                x += item.side
            }
            y += height
        }
        return result
    }

    /// The shelf an item sits on: the one the user put it on while that shelf still exists, otherwise its zone's.
    static func slot(override own: String?, zoneSlot: String?, slots: [String]) -> String? {
        if let own, slots.contains(own) { return own }
        return zoneSlot
    }

    /// What an item remembers after being dropped on a shelf: nothing on its zone's own shelf, so it follows
    /// the zone again; any other shelf, that shelf.
    static func ownSlot(droppedOn slot: String, zoneSlot: String?) -> String? {
        slot == zoneSlot ? nil : slot
    }

    /// Each item's square on its shelf's floor, seen from above: x across the cabinet (photo widths),
    /// y from the back (0) to the front (`depth`). `slot` is the shelf the item sits on (see `slot(override:)`).
    /// Items keep their zone together inside a shelf.
    static func footprints<ID: Hashable>(items: [(id: ID, slot: String, zone: String, name: String, box: [Double]?)],
                                         rects: [String: [Double]], heightRatio: Double) -> [ID: CGRect] {
        var result: [ID: CGRect] = [:]
        for (slot, v) in rects {
            let inSlot = items
                .filter { $0.slot == slot }
                .map { (item: $0, side: side(for: $0.box, heightRatio: heightRatio)) }
                .sorted { ($0.item.zone, -$0.side, $0.item.name) < ($1.item.zone, -$1.side, $1.item.name) }
            let floor = CGRect(x: v[0], y: 0, width: v[2], height: depth)
            result.merge(pack(inSlot.map { (id: $0.item.id, side: $0.side) }, in: floor)) { a, _ in a }
        }
        return result
    }

    /// Detected shelf boxes -> slot names in reach order (middle shelves first, then outward, upper before
    /// lower), plus each name's rectangle. Names go top to bottom: Top shelf, Shelf 2, ..., Bottom shelf.
    static func slots(fromShelves boxes: [[Double]]) -> (slots: [String], rects: [String: [Double]]) {
        let shelves = boxes.filter { $0.count == 4 }.sorted { $0[1] < $1[1] }
        let n = shelves.count
        let names = shelves.indices.map { i in
            n == 1 ? "Shelf" : i == 0 ? "Top shelf" : i == n - 1 ? "Bottom shelf" : "Shelf \(i + 1)"
        }
        let middle = Double(n - 1) / 2
        let reach = shelves.indices.sorted { (abs(Double($0) - middle), $0) < (abs(Double($1) - middle), $1) }
        return (reach.map { names[$0] }, Dictionary(uniqueKeysWithValues: zip(names, shelves)))
    }

    /// A rectangle for every slot: the detected (or older hand-marked) ones, plus equal bands stacked
    /// below them for slots that have none, ordered top to bottom by name.
    static func rects(slots: [String], saved: [String: [Double]]) -> [String: [Double]] {
        var result = saved.filter { slots.contains($0.key) && $0.value.count == 4 }
        let missing = slots.enumerated()
            .filter { result[$0.element] == nil }
            .sorted { (heightRank($0.element), $0.offset) < (heightRank($1.element), $1.offset) }
            .map(\.element)
        guard !missing.isEmpty else { return result }

        let known = Array(result.values)
        let left = known.map { $0[0] }.min() ?? 0
        let right = known.map { $0[0] + $0[2] }.max() ?? 1
        let height = known.isEmpty ? 1 / Double(missing.count) : known.map { $0[3] }.reduce(0, +) / Double(known.count)
        var top = known.map { $0[1] + $0[3] }.max() ?? 0
        for slot in missing {
            result[slot] = [left, top, right - left, height]
            top += height
        }
        return result
    }

    // shortcut: guesses height from words in typed slot names; upgrade if users name slots freely
    private static func heightRank(_ slot: String) -> Int {
        let name = slot.lowercased()
        if name.contains("top") || name.contains("upper") { return 0 }
        if name.contains("bottom") || name.contains("lower") { return 3 }
        if name.contains("third") { return 2 }
        return 1  // middle, second, or a name that says nothing about height
    }

    /// The slot under a drop point, seen from the front (layout space). The smallest rectangle wins; nil if none.
    static func slot(at point: CGPoint, in slotRects: [String: [Double]], heightRatio: Double) -> String? {
        slotRects
            .map { (slot: $0.key, rect: rect($0.value, heightRatio: heightRatio)) }
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }?
            .slot
    }

    static func selfCheck() {
        let shelf = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2)

        let few = pack([(id: 1, side: 0.1), (id: 2, side: 0.1), (id: 3, side: 0.1)], in: shelf)
        assert(few.values.allSatisfy { abs($0.width - 0.1) < 1e-9 }, "items that fit keep their size")

        let many = pack((0..<30).map { (id: $0, side: 0.15) }, in: shelf)
        let packed = Array(many.values)
        assert(packed.count == 30 && packed.allSatisfy { $0.width < 0.15 }, "too many items shrink")
        assert(packed.allSatisfy { shelf.insetBy(dx: -1e-6, dy: -1e-6).contains($0) }, "packed items stay inside the slot")
        for i in packed.indices {
            for j in packed.indices where i < j {
                assert(!packed[i].insetBy(dx: 1e-6, dy: 1e-6).intersects(packed[j].insetBy(dx: 1e-6, dy: 1e-6)),
                       "packed items don't overlap")
            }
        }

        let marked = ["Top": [0, 0, 1, 0.5], "Inner": [0.1, 0.1, 0.2, 0.2]]
        assert(slot(at: CGPoint(x: 0.15, y: 0.15), in: marked, heightRatio: 1) == "Inner", "the smallest slot under a drop wins")
        assert(slot(at: CGPoint(x: 0.5, y: 0.9), in: marked, heightRatio: 1) == nil, "a drop outside every slot returns nil")

        let three = slots(fromShelves: [[0, 0.5, 1, 0.3], [0, 0, 1, 0.3], [0, 0.3, 1, 0.2]])
        assert(three.slots == ["Shelf 2", "Top shelf", "Bottom shelf"], "the middle shelf is easiest to reach")
        assert(three.rects["Top shelf"] == [0, 0, 1, 0.3], "names follow the shelves top to bottom")
        assert(slots(fromShelves: [[0, 0, 1, 1]]).slots == ["Shelf"], "a single shelf is just Shelf")
        assert(slots(fromShelves: (0..<4).map { [0, Double($0) / 4, 1, 0.25] }).slots
               == ["Shelf 2", "Shelf 3", "Top shelf", "Bottom shelf"], "ties go to the upper shelf")

        func noOverlap(_ r: [String: [Double]]) -> Bool {
            let all = r.values.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]).insetBy(dx: 1e-6, dy: 1e-6) }
            return all.indices.allSatisfy { i in all.indices.allSatisfy { j in i == j || !all[i].intersects(all[j]) } }
        }
        let typed = rects(slots: ["Middle shelf", "Top shelf", "Bottom shelf"], saved: [:])
        assert(typed["Top shelf"]![1] < typed["Middle shelf"]![1] && typed["Middle shelf"]![1] < typed["Bottom shelf"]![1],
               "typed slots stack top to bottom by name")
        assert(noOverlap(typed), "stacked bands don't overlap")
        let mixed = rects(slots: ["Top shelf", "Extra", "Old"], saved: ["Top shelf": [0.1, 0.1, 0.8, 0.2], "Gone": [0, 0, 1, 1]])
        assert(mixed.count == 3 && mixed["Gone"] == nil, "only current slots get rectangles")
        assert(mixed["Top shelf"] == [0.1, 0.1, 0.8, 0.2] && noOverlap(mixed), "slots without one go below the detected ones")

        let feet = footprints(items: [(id: 1, slot: "Top shelf", zone: "Tech", name: "a", box: nil),
                                      (id: 2, slot: "Top shelf", zone: "Tech", name: "b", box: [0, 0, 0.9, 0.9])],
                              rects: ["Top shelf": [0.2, 0, 0.5, 0.3]], heightRatio: 1)
        assert(feet.count == 2 && feet.values.allSatisfy { CGRect(x: 0.2, y: 0, width: 0.5, height: depth).insetBy(dx: -1e-6, dy: -1e-6).contains($0) },
               "items sit on their shelf's floor")
        assert(feet[2]!.width > feet[1]!.width, "a bigger item in the photo gets a bigger footprint")

        let pair = ["Left", "Right"]
        assert(slot(override: "Right", zoneSlot: "Left", slots: pair) == "Right", "an item moved on its own sits where it was put")
        assert(slot(override: nil, zoneSlot: "Left", slots: pair) == "Left", "other items follow their zone")
        assert(slot(override: "Gone", zoneSlot: "Left", slots: pair) == "Left", "a move onto a deleted shelf falls back to the zone's")
        assert(slot(override: nil, zoneSlot: nil, slots: pair) == nil, "a zone with no shelf yet shows nowhere")
        assert(ownSlot(droppedOn: "Left", zoneSlot: "Left") == nil, "dropped on its zone's shelf, an item follows the zone again")
        assert(ownSlot(droppedOn: "Right", zoneSlot: "Left") == "Right", "dropped on another shelf, it remembers that shelf")
        let split = footprints(items: [(id: 1, slot: "Left", zone: "Tech", name: "a", box: nil),
                                       (id: 2, slot: "Right", zone: "Tech", name: "b", box: nil)],
                               rects: ["Left": [0, 0, 0.5, 1], "Right": [0.5, 0, 0.5, 1]], heightRatio: 1)
        assert(split[1]!.maxX <= 0.5 + 1e-9 && split[2]!.minX >= 0.5 - 1e-9, "one item moves to another shelf while its zone stays")
    }
}
