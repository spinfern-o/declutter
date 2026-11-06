import Foundation
import Observation

/// Keeps the user's 3D item models from the server on the phone (Application Support/Models): downloads only new or
/// changed files, deletes ones the server dropped, and keeps everything saved when offline.
@MainActor @Observable
final class ModelStore {
    static let shared = ModelStore()
    static let folder = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    private static let fingerprintsFile = folder.appending(path: "fingerprints.json")

    private(set) var version = 0  // bumped when a sync changed anything; the 3D screens reload their models on it

    /// What to download (new or changed) and what to delete (gone from the server). Names become file names on the
    /// phone, so only lowercase letters, digits and underscores are accepted.
    nonisolated static func plan(server: [String: String], saved: [String: String]) -> (download: [String], delete: [String]) {
        let valid = server.filter { $0.key.wholeMatch(of: /[a-z0-9_]+/) != nil }
        return (valid.filter { saved[$0.key] != $0.value }.map(\.key).sorted(),
                saved.keys.filter { valid[$0] == nil }.sorted())
    }

    func sync() async {
        struct Reply: Decodable { let models: [String: String] }
        guard let (data, response) = try? await URLSession.shared.data(from: API.server.appending(path: "models")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return }  // offline: keep what's saved
        let files = FileManager.default
        try? files.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var saved = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.fingerprintsFile))) ?? [:]
        let (download, delete) = Self.plan(server: reply.models, saved: saved)
        for name in delete {
            try? files.removeItem(at: Self.folder.appending(path: "\(name).usdz"))
            saved[name] = nil
        }
        for name in download {
            // a temp file moved into place, so a failed download never leaves a broken model; it's retried next sync
            guard let (temp, response) = try? await URLSession.shared.download(from: API.server.appending(path: "models/files/\(name).usdz")),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let target = Self.folder.appending(path: "\(name).usdz")
            try? files.removeItem(at: target)
            guard (try? files.moveItem(at: temp, to: target)) != nil else { continue }
            saved[name] = reply.models[name]
        }
        try? JSONEncoder().encode(saved).write(to: Self.fingerprintsFile)
        if !download.isEmpty || !delete.isEmpty {
            ModelCatalog.reload()
            version += 1
        }
    }

    static func selfCheck() {
        let saved = ["pen": "aaaa", "book": "bbbb", "old": "cccc"]
        let server = ["pen": "aaaa", "book": "b2b2", "toothbrush": "dddd", "../evil": "eeee", "Bad Name": "ffff"]
        let p = plan(server: server, saved: saved)
        assert(p.download == ["book", "toothbrush"], "new and changed models are downloaded, unchanged ones aren't")
        assert(p.delete == ["old"], "a model the server dropped is deleted")
        assert(!p.download.contains("../evil") && !p.download.contains("Bad Name"), "names that aren't safe file names are ignored")
        assert(plan(server: [:], saved: [:]) == ([], []), "nothing to do")
    }
}
