import ARKit
import Combine
import RealityKit
import SwiftUI

/// A camera view that finds the floor: a reticle where the center of the screen meets it, plus the dots
/// and lines the scan screens have placed. Used only where `ARWorldTrackingConfiguration.isSupported`.
final class FloorAR {
    lazy var view: ARView = {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.scene.addAnchor(anchor)
        anchor.addChild(reticle)
        anchor.addChild(outline)
        update = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in self?.tick() }
        return view
    }()
    /// While set, a line follows the reticle from here (the last tapped point).
    var rubberBand: SIMD3<Float>?

    private let anchor = AnchorEntity(world: .zero)
    private let reticle = ModelEntity(mesh: .generatePlane(width: 0.08, depth: 0.08, cornerRadius: 0.04),
                                      materials: [UnlitMaterial(color: .white)])
    private let outline = Entity()
    private let band = FloorAR.line()
    private var update: Cancellable?

    func run() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        view.session.run(config)  // no reset options: a resumed session keeps its world origin when it can
    }

    func pause() { view.session.pause() }

    /// Where the phone is, in world coordinates.
    var viewer: SIMD3<Float> { view.cameraTransform.translation }

    /// The floor under the center of the screen. The lowest horizontal plane on the ray is the floor, not a
    /// desk; before any plane is found, ARKit's estimate.
    func floorPoint() -> SIMD3<Float>? {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let hit = view.raycast(from: center, allowing: .existingPlaneInfinite, alignment: .horizontal)
            .min { $0.worldTransform.columns.3.y < $1.worldTransform.columns.3.y }
            ?? view.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first
        guard let t = hit?.worldTransform.columns.3 else { return nil }
        return [t.x, t.y, t.z]
    }

    /// Replace the drawn dots and lines.
    func show(dots: [SIMD3<Float>], lines: [(SIMD3<Float>, SIMD3<Float>)]) {
        outline.children.removeAll()
        for p in dots {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [UnlitMaterial(color: .systemYellow)])
            dot.position = p
            outline.addChild(dot)
        }
        for (p, q) in lines {
            let line = FloorAR.line()
            FloorAR.stretch(line, from: p, to: q)
            outline.addChild(line)
        }
    }

    private func tick() {
        let point = floorPoint()
        reticle.isEnabled = point != nil
        if let point { reticle.position = point }
        if let start = rubberBand, let point {
            if band.parent == nil { anchor.addChild(band) }
            FloorAR.stretch(band, from: start, to: point)
        } else {
            band.removeFromParent()
        }
    }

    private static func line() -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: 1), materials: [UnlitMaterial(color: .systemYellow)])
    }

    /// A unit box scaled into a thin bar from p to q.
    private static func stretch(_ line: ModelEntity, from p: SIMD3<Float>, to q: SIMD3<Float>) {
        let length = simd_distance(p, q)
        guard length > 0.001 else { line.scale = .zero; return }
        line.look(at: q, from: (p + q) / 2, relativeTo: nil)  // -z now points at q
        line.scale = [0.008, 0.008, length]
    }
}

/// The AR camera, filling its frame.
struct FloorARView: UIViewRepresentable {
    let ar: FloorAR
    func makeUIView(context: Context) -> ARView { ar.view }
    func updateUIView(_ view: ARView, context: Context) {}
}
