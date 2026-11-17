import Foundation

/// A piece of furniture a real store sells, from the server's catalog (backend/data/catalog.json).
struct Product: Decodable, Identifiable {
    let id: String
    let name: String
    let store: String
    let url: String  // its page at the store
    let price: Double  // US dollars, on the day the catalog says it was checked
    let size_in: [Double]  // width, depth, height in inches, as the store lists them
    let kind: String  // "storage" gets shelves the room plan can fill; anything else is only placed
    let levels: Int?  // a storage piece's shelves or drawers
}

/// A dorm room whose floor size is known (backend/data/dorms.json).
struct Dorm: Decodable {
    let school: String
    let hall: String
    let room: String?  // the room type, like "Double"
    let width_ft: Double
    let length_ft: Double
}

enum Catalog {
    struct Products: Decodable {
        let checked: String  // the day the prices were read off the stores' pages
        let products: [Product]
    }

    private struct Dorms: Decodable { let dorms: [Dorm] }

    static func products() async throws -> Products {
        let all: Products = try await get("catalog.json")
        return Products(checked: all.checked,
                        products: all.products.filter { Furniture.usable(url: $0.url, sizeInches: $0.size_in) })
    }

    static func dorms() async throws -> [Dorm] {
        let all: Dorms = try await get("dorms.json")
        return all.dorms.filter { (5...60).contains($0.width_ft) && (5...60).contains($0.length_ft) }
    }

    private static func get<T: Decodable>(_ file: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: API.server.appending(path: "data/\(file)"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
