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
    @Relationship(deleteRule: .cascade, inverse: \Item.space) var items: [Item] = []

    init(name: String, photo: Data, zones: [String]) {
        self.name = name
        self.photo = photo
        self.zones = zones
    }
}

@Model
final class Item {
    var name: String
    var className: String  // model class, or "manual" for items the user added
    var zone: String
    var confidence: Double?
    @Attribute(.externalStorage) var cutout: Data?
    var space: Space?

    init(name: String, className: String, zone: String, confidence: Double? = nil, cutout: Data? = nil) {
        self.name = name
        self.className = className
        self.zone = zone
        self.confidence = confidence
        self.cutout = cutout
    }
}

extension Array where Element == Item {
    /// Relationship arrays have no stable order; the id tiebreak stops same-name rows swapping.
    var byName: [Item] { sorted { ($0.name, $0.persistentModelID) < ($1.name, $1.persistentModelID) } }
}
