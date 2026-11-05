import Foundation
import simd

/// Floor-plan math for the room scan: turns AR world taps (meters, y up) into the room frame (see Room).
enum RoomGeometry {
    /// World floor -> room frame: `origin` becomes [0, 0] and the direction `x` becomes +x.
    struct Frame {
        var origin: SIMD2<Double>
        var x: SIMD2<Double>  // unit length

        /// A world point's [x, z] in the room. Room z = x cross y-up, so the frame stays right-handed.
        func room(_ world: SIMD3<Float>) -> SIMD2<Double> {
            let d = flat(world) - origin
            return [simd_dot(d, x), simd_dot(d, [-x.y, x.x])]
        }
    }

    /// The floor position of a world point: its (x, z), height dropped.
    static func flat(_ p: SIMD3<Float>) -> SIMD2<Double> { [Double(p.x), Double(p.z)] }

    /// A frame with `a` at the origin and the wall a -> b along +x.
    static func frame(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Frame {
        Frame(origin: flat(a), x: simd_normalize(flat(b) - flat(a)))
    }

    /// Tapped floor corners -> the room's `corners`, plus the frame that maps later world taps into it.
    static func normalize(_ worldCorners: [SIMD3<Float>]) -> (corners: [[Double]], frame: Frame)? {
        var taps: [SIMD3<Float>] = []
        for p in worldCorners where taps.last.map({ simd_distance(flat($0), flat(p)) >= 0.1 }) ?? true {
            taps.append(p)
        }
        if let first = taps.first, taps.count > 1, simd_distance(flat(first), flat(taps.last!)) < 0.1 { taps.removeLast() }
        guard taps.count >= 3 else { return nil }

        func outline(_ taps: [SIMD3<Float>]) -> (corners: [SIMD2<Double>], frame: Frame) {
            let f = frame(taps[0], taps[1])
            return (taps.map(f.room), f)
        }
        var (corners, f) = outline(taps)
        let twiceArea = zip(corners, corners.dropFirst() + [corners[0]]).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
        guard abs(twiceArea) >= 0.5 else { return nil }  // corners in a line (under 0.25 m² of floor) are no room
        if twiceArea < 0 {  // the room lies toward -z of wall 0: go around the other way, along the same wall
            (corners, f) = outline([taps[1], taps[0]] + taps.dropFirst(2).reversed())
        }
        return (corners.map { [$0.x, $0.y] }, f)
    }

    /// Re-align a new AR session to a saved room: `a` and `b` are the two ends of its first wall, tapped in
    /// either order; `viewer` (the phone, standing in the room) decides which end is corner 0.
    /// nil when the two taps are under 10 cm apart: no direction to line up on.
    static func align(_ a: SIMD3<Float>, _ b: SIMD3<Float>, viewer: SIMD3<Float>) -> Frame? {
        guard simd_distance(flat(a), flat(b)) >= 0.1 else { return nil }
        let f = frame(a, b)
        return f.room(viewer).y >= 0 ? f : frame(b, a)
    }

    /// Two taps at a cabinet's front corners (room frame, either order) -> its `spot`; the front faces `viewer`.
    /// nil when the taps are under 10 cm apart.
    static func spot(_ a: SIMD2<Double>, _ b: SIMD2<Double>, viewer: SIMD2<Double>,
                     depth: Double = 0.45, height: Double = 0.9) -> [Double]? {
        guard simd_distance(a, b) >= 0.1 else { return nil }  // one point twice: no width, no facing
        let mid = (a + b) / 2
        var front = simd_normalize(b - a)
        front = [-front.y, front.x]  // a, b seen from the front go left to right
        if simd_dot(front, viewer - mid) < 0 { front = -front }
        let center = mid - front * depth / 2
        return [center.x, center.y, atan2(front.x, front.y), simd_distance(a, b), depth, height]
    }

    static func selfCheck() {
        func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-4 } }
        func near(_ a: [[Double]], _ b: [[Double]]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { near($0, $1) } }
        func world(_ x: Float, _ z: Float) -> SIMD3<Float> { [x, -1.3, z] }  // the floor sits below the AR origin

        // a 4 x 3 m room, tapped somewhere off the world origin with wall 0 running along world -z
        let room = [[0.0, 0], [4, 0], [4, 3], [0, 3]]
        let taps = [world(2, 1), world(2, -3), world(5, -3), world(5, 1)]
        assert(near(normalize(taps)?.corners ?? [], room), "corner 0 at the origin, wall 0 along +x")
        assert(near(normalize(taps.reversed())?.corners ?? [], room),
               "the other way around gives the same room (it lies toward +z of wall 0)")
        assert(near(normalize([taps[0], world(2.05, 1)] + taps.dropFirst() + [world(2, 1.03)])?.corners ?? [], room),
               "taps under 10 cm apart, and a last tap back on the first corner, are dropped")
        assert(normalize([world(0, 0), world(0.05, 0)]) == nil, "fewer than 3 distinct corners is no room")
        assert(normalize([world(0, 0), world(1, 0), world(2, 0)]) == nil, "corners in a straight line are no room")

        let f = normalize(taps)!.frame
        assert(simd_distance(f.room(world(5, -1)), [2, 3]) < 1e-4, "later taps map into the same frame")
        let again = align(world(2, -3), world(2, 1), viewer: [3, 0, -1])!
        assert(simd_distance(again.room(world(5, -1)), [2, 3]) < 1e-4, "re-aligning on wall 0 tapped backwards still finds corner 0")

        // the sample room's two cabinets (Room.sample): against wall 0 and against wall 1
        assert(align(world(1, 1), world(1.05, 1), viewer: world(0, 0)) == nil, "a wall under 10 cm long is no wall")
        assert(spot([1, 1], [1.05, 1], viewer: [0, 0]) == nil, "front corners under 10 cm apart are no cabinet")
        assert(near(spot([0.6, 0.475], [1.4, 0.475], viewer: [1, 2]) ?? [], [1, 0.25, 0, 0.8, 0.45, 0.9]),
               "a cabinet on wall 0 faces +z, its center behind the front edge")
        assert(near(spot([3.525, 2.3], [3.525, 1.7], viewer: [2, 2], height: 1.2) ?? [], [3.75, 2, -Double.pi / 2, 0.6, 0.45, 1.2]),
               "a cabinet on wall 1 faces -x, whichever front corner was tapped first")
    }
}
