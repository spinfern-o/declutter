import Foundation
import SwiftData

/// A room the user outlined, with the cabinets ("messy spots") standing in it.
/// Room frame: meters, y up, floor at y = 0; x and z lie on the floor. Corner 0 is at the origin and
/// the first wall runs from corner 0 to corner 1 along +x; corners go around the room in order.
@Model
final class Room {
    var name: String
    var createdAt = Date()
    var corners: [[Double]]  // the floor outline: [x, z] per corner, in the room frame
    var wallHeight = 2.4
    @Relationship(deleteRule: .nullify, inverse: \Space.room) var spaces: [Space] = []

    init(name: String, corners: [[Double]]) {
        self.name = name
        self.corners = corners
    }

    #if DEBUG
    /// A 4 x 3.5 m room with up to two existing cabinets against its walls, to test without scanning.
    static func sample(in context: ModelContext) -> Room {
        let room = Room(name: "Sample Room", corners: [[0, 0], [4, 0], [4, 3.5], [0, 3.5]])
        context.insert(room)
        let loose = (try? context.fetch(FetchDescriptor<Space>()))?.filter { $0.room == nil } ?? []
        let spots: [[Double]] = [[1, 0.25, 0, 0.8, 0.45, 0.9],  // against wall 0, facing into the room
                                 [3.75, 2, -Double.pi / 2, 0.6, 0.45, 1.2]]  // against wall 1
        for (space, spot) in zip(loose, spots) {
            space.room = room
            space.spot = spot
        }
        try? context.save()
        return room
    }
    #endif
}
