import Foundation
import SwiftData

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
