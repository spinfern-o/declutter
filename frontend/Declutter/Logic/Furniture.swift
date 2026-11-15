import Foundation

/// Rules for furniture added from the marketplace and for dorm rooms: store units into the room's meters,
/// where a new piece first stands, how it turns, and the shelves a storage piece gets. Pure functions, self-checked.
enum Furniture {
    static let inch = 0.0254, foot = 0.3048  // meters

    /// The catalog comes from the server: only secure store links, and sizes a room could hold.
    static func usable(url: String, sizeInches: [Double]) -> Bool {
        url.hasPrefix("https://") && URL(string: url) != nil
            && sizeInches.count == 3 && sizeInches.allSatisfy { (1...120).contains($0) }
    }

    /// [width, depth, height] in inches, as stores list them, in meters.
    static func meters(_ inches: [Double]) -> [Double] { inches.map { $0 * inch } }

    /// "30 × 15 × 30 in": width, depth, height to the nearest inch.
    static func label(sizeInches: [Double]) -> String {
        sizeInches.map { String(Int($0.rounded())) }.joined(separator: " × ") + " in"
    }

    /// Where a new piece first stands: the middle of the room, front toward +z. The user drags it from there.
    static func spot(size: [Double], in corners: [[Double]]) -> [Double] {
        let xs = corners.map { $0[0] }, zs = corners.map { $0[1] }
        let x = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, z = ((zs.min() ?? 0) + (zs.max() ?? 0)) / 2
        return RoomGeometry.clamp([x, z, 0, size[0], size[1], size[2]], in: corners)
    }

    /// The same spot turned a quarter of the way around, kept inside the room.
    static func turned(_ spot: [Double], in corners: [[Double]]) -> [Double] {
        guard spot.count == 6 else { return spot }
        var result = spot
        result[2] = (spot[2] + .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return RoomGeometry.clamp(result, in: corners)
    }

    /// A storage piece's shelves as equal bands, top to bottom: the same [x, y, w, h] fractions detected shelves use.
    static func shelves(_ levels: Int) -> [[Double]] {
        let n = max(levels, 1)
        return (0..<n).map { [0, Double($0) / Double(n), 1, 1 / Double(n)] }
    }

    /// A rectangular room from a dorm's floor size in feet: wall 0 along +x, the room toward +z.
    static func corners(widthFeet: Double, lengthFeet: Double) -> [[Double]] {
        let w = widthFeet * foot, l = lengthFeet * foot
        return [[0, 0], [w, 0], [w, l], [0, l]]
    }

    static func selfCheck() {
        assert(usable(url: "https://www.ikea.com/us/en/p/x/", sizeInches: [30, 15, 30]), "a store page with a real size is usable")
        assert(!usable(url: "http://www.ikea.com/x", sizeInches: [30, 15, 30]), "only secure links are opened")
        assert(!usable(url: "javascript:alert(1)", sizeInches: [30, 15, 30]), "anything that isn't a web page is dropped")
        assert(!usable(url: "https://a.com", sizeInches: [30, 15]) && !usable(url: "https://a.com", sizeInches: [0, 15, 30]),
               "a piece needs a width, a depth and a height a room could hold")

        func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }
        assert(near(meters([100, 50, 10]), [2.54, 1.27, 0.254]), "inches become meters")
        assert(label(sizeInches: [30.125, 15.375, 30.125]) == "30 × 15 × 30 in", "sizes read to the nearest inch")

        let box = [[0.0, 0], [4, 0], [4, 3], [0, 3]]
        assert(near(spot(size: [0.8, 0.4, 0.9], in: box), [2, 1.5, 0, 0.8, 0.4, 0.9]), "a new piece stands in the middle of the room")
        assert(near(spot(size: [5, 0.4, 1], in: box), [2, 1.5, 0, 5, 0.4, 1]), "a piece too big for the room is still centered")

        let against = turned([2, 0.2, 0, 0.8, 0.4, 0.9], in: box)  // flat against wall 0, then turned
        assert(abs(against[2] - .pi / 2) < 1e-9 && abs(against[1] - 0.4) < 1e-9, "a turned piece moves off the wall it would cross")
        var full = [2, 1.5, 0, 0.8, 0.4, 0.9]
        for _ in 0..<4 { full = turned(full, in: box) }
        assert(abs(sin(full[2])) < 1e-9 && cos(full[2]) > 0 && near(Array(full[..<2]), [2, 1.5]), "four quarter turns bring it back")

        let three = shelves(3)
        assert(three.count == 3 && near(three[0], [0, 0, 1, 1.0 / 3]) && abs(three[2][1] + three[2][3] - 1) < 1e-9,
               "shelves are equal bands that fill the piece")
        assert(shelves(0).count == 1, "a storage piece has at least one shelf")
        assert(CabinetLayout.slots(fromShelves: three).slots == ["Shelf 2", "Top shelf", "Bottom shelf"],
               "a storage piece gets the same shelf names and reach order as a photographed cabinet")

        assert(near(corners(widthFeet: 10, lengthFeet: 12)[2], [3.048, 3.6576]), "a dorm's feet become the room's meters")
    }
}
