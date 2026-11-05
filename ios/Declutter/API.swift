import UIKit

struct DetectResponse: Decodable {
    struct Found: Decodable {
        let `class`: String
        let zone: String
        let confidence: Double
        let cutout: String  // base64 PNG
    }

    let zones: [String]
    let items: [Found]
}

enum API {
    // ATS doesn't apply to localhost, so plain HTTP works in the simulator
    #if DEBUG
    static let server = URL(string: "http://localhost:8000")!
    #else
    static let server = URL(string: "https://declutter-api.fly.dev")!  // match `app` in fly.toml
    #endif

    static func detect(jpeg: Data) async throws -> DetectResponse {
        var request = URLRequest(url: server.appending(path: "detect"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60  // the first call may have to wake a stopped server
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(DetectResponse.self, from: data)
    }

    /// Upright JPEG, long side at most 2048 px: plenty for the model, and well under the server's 15 MB cap.
    static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, 2048 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }
}
