import CoreGraphics

/// Geometry for the photo screen. Saved boxes and slot rectangles are [x, y, w, h] fractions of the
/// photo's width and height; layout works in "photo widths" (x and y both divided by the width) so an
/// icon's square stays square on any photo shape. Pure functions, so they can be self-checked.
enum PhotoLayout {
    static let defaultSide = 0.12  // icon size for items with no box: manual items and cabinets saved earlier

    /// A saved [x, y, w, h] fraction rectangle, in layout space. `heightRatio` is photo height / width.
    static func rect(_ v: [Double], heightRatio: Double) -> CGRect {
        CGRect(x: v[0], y: v[1] * heightRatio, width: v[2], height: v[3] * heightRatio)
    }

    /// Icon size for an item: about the size it was in the photo, clamped so tiny items stay visible.
    static func side(for box: [Double]?, heightRatio: Double) -> Double {
        guard let box, box.count == 4 else { return defaultSide }
        return min(max((box[2] + box[3] * heightRatio) / 2, 0.05), 0.25)
    }

    /// Where the icon sits before organizing: centered on the real item. nil for items with no box.
    static func original(_ box: [Double]?, heightRatio: Double) -> CGRect? {
        guard let box, box.count == 4 else { return nil }
        let r = rect(box, heightRatio: heightRatio)
        let s = side(for: box, heightRatio: heightRatio)
        return CGRect(x: r.midX - s / 2, y: r.midY - s / 2, width: s, height: s)
    }

    /// Square icons laid out in rows inside `rect`, in the order given, all shrunk by one shared factor
    /// (never grown) until they fit. Icons sit on the bottom of their row, like things on a shelf.
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

    /// Where every placed item's icon goes, in layout space. Items keep their zone together inside a
    /// slot. Items whose slot has no marked rectangle get no position.
    static func positions<ID: Hashable>(items: [(id: ID, zone: String, name: String, box: [Double]?)],
                                        placement: [String: String], slotRects: [String: [Double]],
                                        heightRatio: Double) -> [ID: CGRect] {
        var result: [ID: CGRect] = [:]
        for (slot, v) in slotRects {
            let inSlot = items
                .filter { placement[$0.zone] == slot }
                .map { (item: $0, side: side(for: $0.box, heightRatio: heightRatio)) }
                .sorted { ($0.item.zone, -$0.side, $0.item.name) < ($1.item.zone, -$1.side, $1.item.name) }
            result.merge(pack(inSlot.map { (id: $0.item.id, side: $0.side) }, in: rect(v, heightRatio: heightRatio))) { a, _ in a }
        }
        return result
    }

    /// The slot under a drop point (layout space). The smallest marked rectangle wins; nil if none.
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
        let rects = Array(many.values)
        assert(rects.count == 30 && rects.allSatisfy { $0.width < 0.15 }, "too many items shrink")
        assert(rects.allSatisfy { shelf.insetBy(dx: -1e-6, dy: -1e-6).contains($0) }, "packed icons stay inside the slot")
        for i in rects.indices {
            for j in rects.indices where i < j {
                assert(!rects[i].insetBy(dx: 1e-6, dy: 1e-6).intersects(rects[j].insetBy(dx: 1e-6, dy: 1e-6)),
                       "packed icons don't overlap")
            }
        }

        let slots = ["Top": [0, 0, 1, 0.5], "Inner": [0.1, 0.1, 0.2, 0.2]]
        assert(slot(at: CGPoint(x: 0.15, y: 0.15), in: slots, heightRatio: 1) == "Inner", "the smallest slot under a drop wins")
        assert(slot(at: CGPoint(x: 0.5, y: 0.9), in: slots, heightRatio: 1) == nil, "a drop outside every slot returns nil")
    }
}
