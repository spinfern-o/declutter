import Foundation
import SwiftData

@Model
final class Item {
    var name: String
    var className: String  // model class, or "manual" for items the user added
    var zone: String
    var confidence: Double?
    @Attribute(.externalStorage) var cutout: Data?
    var box: [Double]?  // where it sat in the photo: [x, y, w, h] as fractions; nil for manual and older items
    var space: Space?  // the cabinet it was detected in
    var destination: Space?  // the spot the user moved it to in its room; wins over the room plan

    init(name: String, className: String, zone: String, confidence: Double? = nil, cutout: Data? = nil,
         box: [Double]? = nil) {
        self.name = name
        self.className = className
        self.zone = zone
        self.confidence = confidence
        self.cutout = cutout
        self.box = box
    }
}

extension Array where Element == Item {
    /// Relationship arrays have no stable order; the id tiebreak stops same-name rows swapping.
    var byName: [Item] { sorted { ($0.name, $0.persistentModelID) < ($1.name, $1.persistentModelID) } }
}
