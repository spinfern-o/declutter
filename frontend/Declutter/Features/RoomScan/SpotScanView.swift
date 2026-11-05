import ARKit
import SwiftData
import SwiftUI

/// Mark where a messy spot (a cabinet) stands in a room. In AR: re-tap the room's first wall to line up
/// with the saved outline, tap the cabinet's two front corners, then photograph it or pick an existing
/// cabinet. Without AR (the Simulator): pick an existing cabinet and type its width.
struct SpotScanView: View {
    let room: Room

    var body: some View {
        if ARWorldTrackingConfiguration.isSupported { SpotTap(room: room) } else { TypedSpot(room: room) }
    }
}

private struct SpotTap: View {
    let room: Room
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Space.createdAt, order: .reverse) private var spaces: [Space]
    @State private var ar = FloorAR()
    @State private var taps: [SIMD3<Float>] = []  // first wall's two ends, then the cabinet's two front corners
    @State private var frame: RoomGeometry.Frame?  // this AR session's world -> room, from the first wall
    @State private var spot: [Double]?
    @State private var height = 0.9
    @State private var choosing = false
    @State private var showCamera = false
    @State private var pending: Data?  // photo waiting on the server; kept so Retry doesn't lose it
    @State private var failed = false

    var body: some View {
        FloorARView(ar: ar)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top) {
                Text(instruction)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    if spot != nil {
                        Stepper("Height \(height, format: .number.precision(.fractionLength(2))) m",
                                value: $height, in: 0.2...2.5, step: 0.05)
                        HStack {
                            Button("Take Photo") { ar.pause(); showCamera = true }
                            Spacer()
                            Button("Use Existing Cabinet") { choosing = true }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Button("Cancel") { dismiss() }
                        Spacer()
                        Button("Undo") { undo() }.disabled(taps.isEmpty)
                        Spacer()
                        Button("Add Point") { add() }.disabled(taps.count == 4)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .disabled(pending != nil)
            }
            .overlay {
                if pending != nil && !failed {
                    ProgressView("Sorting…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .onAppear { ar.run() }
            .onDisappear { ar.pause() }
            .onChange(of: taps) {
                ar.show(dots: taps, lines: stride(from: 0, to: taps.count - 1, by: 2).map { (taps[$0], taps[$0 + 1]) })
                ar.rubberBand = taps.count.isMultiple(of: 2) ? nil : taps.last
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: { if pending == nil { ar.run() } }) {
                CameraPicker { image in
                    if let jpeg = API.jpeg(image) { sort(jpeg) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $choosing) {
                NavigationStack {
                    let loose = spaces.filter { $0.room == nil }
                    List(loose) { space in
                        Button(space.name) { choosing = false; place(space) }
                    }
                    .overlay {
                        if loose.isEmpty {
                            ContentUnavailableView("No loose cabinets", systemImage: "cabinet",
                                                   description: Text("Every cabinet is already in a room. Take a photo instead."))
                        }
                    }
                    .navigationTitle("Use Existing Cabinet")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Cancel") { choosing = false } }
                }
            }
            .alert("Couldn't sort this photo", isPresented: $failed) {
                Button("Retry") { if let pending { sort(pending) } }
                Button("Cancel", role: .cancel) { pending = nil; ar.run() }
            } message: {
                Text("Check your connection and try again.")
            }
    }

    private var instruction: String {
        let wall = simd_length(SIMD2(room.corners[1][0], room.corners[1][1]))  // corner 0 is the origin
        let wallText = wall.formatted(.number.precision(.fractionLength(1)))
        switch taps.count {
        case 0: return "Aim the dot at one end of the room's first wall (one of the first two corners you added, \(wallText) m apart) and tap Add Point."
        case 1: return "Now the other end of the first wall."
        case 2, 3:
            let measured = simd_distance(RoomGeometry.flat(taps[0]), RoomGeometry.flat(taps[1]))
            let off = abs(measured - wall) > 0.3
                ? "That wall measured \(measured.formatted(.number.precision(.fractionLength(1)))) m, not \(wallText) m: Undo and re-tap it.\n" : ""
            return off + (taps.count == 2 ? "Now one of the cabinet's front corners, on the floor." : "Now its other front corner.")
        default: return "Set its height, then photograph it or pick a cabinet you already have."
        }
    }

    private func add() {
        guard let p = ar.floorPoint() else { return }
        taps.append(p)
        if taps.count == 2 { frame = RoomGeometry.align(taps[0], taps[1], viewer: ar.viewer) }
        if taps.count == 4, let frame {
            spot = RoomGeometry.spot(frame.room(taps[2]), frame.room(taps[3]), viewer: frame.room(ar.viewer))
        }
    }

    private func undo() {
        taps.removeLast()
        if taps.count < 4 { spot = nil }
        if taps.count < 2 { frame = nil }
    }

    private func sort(_ jpeg: Data) {
        pending = jpeg
        Task {
            do {
                let response = try await API.detect(jpeg: jpeg)
                place(Space.make(name: "Cabinet \(spaces.count + 1)", photo: jpeg, response: response, in: context))
            } catch {
                failed = true
            }
        }
    }

    private func place(_ space: Space) {
        guard var spot else { return }
        spot[5] = height
        space.room = room
        space.spot = spot
        try? context.save()
        dismiss()
    }
}

/// The fallback: an existing cabinet with a typed width, against the first wall after the others there.
private struct TypedSpot: View {
    let room: Room
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Space.createdAt, order: .reverse) private var spaces: [Space]
    @State private var chosen: Space?
    @State private var width = 0.8

    var body: some View {
        NavigationStack {
            Form {
                Section("Cabinet") {
                    let loose = spaces.filter { $0.room == nil }
                    if loose.isEmpty {
                        Text("Photograph a cabinet in the Cabinets tab first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(loose) { space in
                        Button {
                            chosen = space
                        } label: {
                            LabeledContent(space.name) {
                                if chosen?.persistentModelID == space.persistentModelID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("Size") {
                    Stepper("Width \(width, format: .number.precision(.fractionLength(1))) m", value: $width, in: 0.2...3, step: 0.1)
                }
            }
            .navigationTitle("Add Messy Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(chosen == nil)
                }
            }
        }
    }

    private func add() {
        guard let chosen else { return }
        let depth = 0.45
        // against wall 0 (z = 0), facing into the room, to the right of the spots already there
        let onWall = room.spaces.compactMap(\.spot).filter { abs($0[1] - depth / 2) < 0.01 && $0[2] == 0 }
        let left = (onWall.map { $0[0] + $0[3] / 2 }.max() ?? 0) + 0.05
        chosen.room = room
        chosen.spot = [left + width / 2, depth / 2, 0, width, depth, 0.9]
        try? context.save()
        dismiss()
    }
}
