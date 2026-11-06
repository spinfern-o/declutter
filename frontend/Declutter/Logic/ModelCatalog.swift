import Foundation

/// Which of your 3D models an item gets: downloaded from the server (ModelStore) or built into the app
/// (Resources/Models). The file name is the object: a class name like "cardboard_box", or any object like
/// "water_bottle" for items named that way.
enum ModelCatalog {
    private(set) static var objects = list()

    static func reload() { objects = list() }

    private static func list() -> [String] {
        let downloaded = (try? FileManager.default.contentsOfDirectory(at: ModelStore.folder, includingPropertiesForKeys: nil)) ?? []
        let bundled = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? []
        return Set((downloaded + bundled).filter { $0.pathExtension == "usdz" }
            .map { $0.deletingPathExtension().lastPathComponent }).sorted()
    }

    /// The model file: the server's copy when there is one, so updates win over a copy built into the app.
    static func url(for object: String) -> URL? {
        let downloaded = ModelStore.folder.appending(path: "\(object).usdz")
        return FileManager.default.fileExists(atPath: downloaded.path) ? downloaded
            : Bundle.main.url(forResource: object, withExtension: "usdz")
    }

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
