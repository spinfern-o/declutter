import ARKit
import SwiftData
import SwiftUI

/// Outline a new room by tapping its floor corners in AR. Where AR isn't available (the Simulator), a
/// typed width and length make a rectangular room instead.
struct RoomScanView: View {
    var body: some View {
        if ARWorldTrackingConfiguration.isSupported { CornerScan() } else { TypedRoom() }
    }
}

/// Walk around the room, aiming the dot at each floor corner in turn.
private struct CornerScan: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var ar = FloorAR()
    @State private var taps: [SIMD3<Float>] = []
    @State private var naming = false
    @State private var name = "My Room"

    var body: some View {
        let room = RoomGeometry.normalize(taps)
        FloorARView(ar: ar)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top) {
                Text(taps.isEmpty
                     ? "Aim the dot at a floor corner and tap Add Corner. Start at a corner you can find again: you'll tap the first wall's two corners to place cabinets later."
                     : "Go around the room corner by corner. \(taps.count) added.")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Undo") { taps.removeLast() }.disabled(taps.isEmpty)
                    Spacer()
                    Button("Add Corner") { if let p = ar.floorPoint() { taps.append(p) } }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Done") { naming = true }.disabled(room == nil)
                }
                .padding()
                .background(.regularMaterial)
            }
            .onAppear { ar.run() }
            .onDisappear { ar.pause() }
            .onChange(of: taps) {
                let closing = taps.count >= 3 ? [(taps.last!, taps[0])] : []
                ar.show(dots: taps, lines: Array(zip(taps, taps.dropFirst())) + closing)
                ar.rubberBand = taps.last
            }
            .alert("Name this room", isPresented: $naming) {
                TextField("Name", text: $name)
                Button("Save") {
                    guard let room, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    context.insert(Room(name: name.trimmingCharacters(in: .whitespaces), corners: room.corners))
                    try? context.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

/// The fallback: a rectangle from a typed width and length.
private struct TypedRoom: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My Room"
    @State private var width = 4.0
    @State private var length = 3.5

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Stepper("Width \(width, format: .number.precision(.fractionLength(1))) m", value: $width, in: 1...15, step: 0.1)
                Stepper("Length \(length, format: .number.precision(.fractionLength(1))) m", value: $length, in: 1...15, step: 0.1)
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let corners = [[0, 0], [width, 0], [width, length], [0, length]]  // wall 0 along +x, room toward +z
        context.insert(Room(name: name.trimmingCharacters(in: .whitespaces), corners: corners))
        try? context.save()
        dismiss()
    }
}
