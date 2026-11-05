import UIKit

/// The cartoon picture for an item, from Resources/Icons (built by backend/tools/import_icons.py).
enum IconCatalog {
    /// object -> words that should show its picture; the picture file is <object>.png
    static let catalog: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }()

    private static var cache: [String: UIImage] = [:]

    /// Which picture an item gets: a word in its name first (so renamed and manual items find theirs),
    /// then the model's class, then the generic "other" picture. Never the realistic cutout.
    static func object(name: String, className: String, in catalog: [String: [String]] = IconCatalog.catalog) -> String? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let phrase = " " + words.joined(separator: " ") + " "
        // crude singular so "pens" finds "pen"; longer words only, so "glass" etc. aren't mangled
        let singular = " " + words.map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
            .joined(separator: " ") + " "

        var best: (object: String, length: Int)?
        for (object, keywords) in catalog.sorted(by: { $0.key < $1.key }) {
            for keyword in keywords where keyword.count > (best?.length ?? 0)
                && (phrase.contains(" \(keyword) ") || singular.contains(" \(keyword) ")) {
                best = (object, keyword.count)  // the longest matching phrase wins: "cardboard box" over "box"
            }
        }
        if let best { return best.object }
        if catalog[className] != nil { return className }
        return catalog["other"] != nil ? "other" : nil
    }

    static func image(name: String, className: String) -> UIImage {
        guard let object = object(name: name, className: className) else { return fallback }
        if let cached = cache[object] { return cached }
        guard let url = Bundle.main.url(forResource: object, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { return fallback }
        cache[object] = image
        return image
    }

    private static let fallback = UIImage(systemName: "shippingbox")!  // only if the icons are missing from the build

    static func selfCheck() {
        let sample = ["toothbrush": ["toothbrush"], "cardboard_box": ["box", "cardboard box"],
                      "pen": ["pen"], "other": ["other"]]
        assert(object(name: "toothbrush", className: "toothbrush", in: sample) == "toothbrush", "a class finds its picture")
        assert(object(name: "Electric toothbrush", className: "manual", in: sample) == "toothbrush",
               "a word in the name finds a picture")
        assert(object(name: "red pens", className: "manual", in: sample) == "pen", "plurals match")
        assert(object(name: "sunglasses", className: "manual", in: sample) == "other",
               "an unknown item gets the generic picture")
        assert(!catalog.isEmpty, "Resources/Icons/catalog.json is missing from the app bundle")
        assert(object(name: "zzz", className: "zzz") != nil, "every item gets some picture")
    }
}
