import Foundation

/// Which of your 3D models (Resources/Models/<object>.usdz) an item gets. The file name is the object:
/// a class name like "cardboard_box", or any object like "water_bottle" for items named that way.
enum ModelCatalog {
    static let objects: [String] = (Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted()

    /// A word in the item's name first (so renamed and manual items find theirs), then the model's
    /// class. nil means no model yet: the scene shows a plain box.
    static func object(name: String, className: String, in objects: [String] = ModelCatalog.objects) -> String? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let phrase = " " + words.joined(separator: " ") + " "
        // crude singular so "pens" finds "pen"; longer words only, so "glass" etc. aren't mangled
        let singular = " " + words.map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
            .joined(separator: " ") + " "

        var best: (object: String, length: Int)?
        for object in objects {
            let keyword = object.lowercased().replacingOccurrences(of: "_", with: " ")
            if keyword.count > (best?.length ?? 0)
                && (phrase.contains(" \(keyword) ") || singular.contains(" \(keyword) ")) {
                best = (object, keyword.count)  // the longest matching phrase wins: "water bottle" over "bottle"
            }
        }
        if let best { return best.object }
        return objects.contains(className) ? className : nil
    }

    static func selfCheck() {
        let sample = ["bottle", "cardboard_box", "pen", "toothbrush", "water_bottle"]
        assert(object(name: "toothbrush", className: "toothbrush", in: sample) == "toothbrush", "a class finds its model")
        assert(object(name: "Electric toothbrush", className: "manual", in: sample) == "toothbrush",
               "a word in the name finds a model")
        assert(object(name: "red pens", className: "manual", in: sample) == "pen", "plurals match")
        assert(object(name: "Big water bottles", className: "bottle", in: sample) == "water_bottle",
               "the longest matching name wins")
        assert(object(name: "Tissues", className: "cardboard_box", in: sample) == "cardboard_box",
               "with no name match, the class decides")
        assert(object(name: "sunglasses", className: "manual", in: sample) == nil, "no model means a plain box")
    }
}
