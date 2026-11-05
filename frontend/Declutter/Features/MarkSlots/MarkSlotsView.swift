import SwiftData
import SwiftUI

/// The plan on the user's own photo. It opens as the organized picture, with each cartoon already in
/// its shelf or drawer. "Original" switches to the photo as taken; marking mode outlines each slot.
struct MarkSlotsView: View {
    @Bindable var space: Space
    @State private var photo: UIImage?
    @State private var mode = Mode.organized
    @State private var markingIndex = 0
    @State private var showOutlines = true

    private enum Mode { case organized, original, marking }

    /// Slots holding a zone that have no outline yet; the picture can't be drawn until these are marked.
    private var unmarked: [String] {
        let used = Set(space.placement.values)
        return space.slots.filter { used.contains($0) && space.slotRects[$0] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Photo of \(space.name)")
                    .overlay {
                        GeometryReader { geo in
                            if mode == .marking, space.slots.indices.contains(markingIndex) {
                                SlotDrawingLayer(space: space, size: geo.size, slot: space.slots[markingIndex])
                            } else {
                                CartoonLayer(space: space, size: geo.size, organized: mode == .organized)
                                if mode == .organized && showOutlines {
                                    // on top so slot names stay readable; outlines ignore touches, so drags still work
                                    SlotOutlines(rects: space.slotRects, size: geo.size)
                                }
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
            }
            if mode == .marking {
                markingControls
            } else if mode == .organized {
                tossStrip
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(mode == .marking ? "Mark Slots" : "On Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode != .marking {
                ToolbarItem(placement: .primaryAction) {
                    Button(mode == .organized ? "Original" : "Organized") {
                        withAnimation(.spring(duration: 0.8)) {
                            mode = mode == .organized ? .original : .organized
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Mark Slots", systemImage: "rectangle.dashed") {
                            markingIndex = 0
                            mode = .marking
                        }
                        Toggle("Show Outlines", systemImage: "square.dashed", isOn: $showOutlines)
                    } label: {
                        Label("Options", systemImage: "ellipsis")
                    }
                }
            }
        }
        .onAppear {
            photo = UIImage(data: space.photo)
            if let first = unmarked.first, let index = space.slots.firstIndex(of: first) {
                markingIndex = index
                mode = .marking
            }
        }
    }

    @ViewBuilder private var markingControls: some View {
        if space.slots.indices.contains(markingIndex) {
            let slot = space.slots[markingIndex]
            let last = markingIndex == space.slots.count - 1
            VStack(alignment: .leading, spacing: 8) {
                Text("Slot \(markingIndex + 1) of \(space.slots.count): \(slot)")
                    .font(.headline)
                Text(space.slotRects[slot] == nil ? "Drag across the photo to outline it." : "Outlined. Drag again to redraw it.")
                    .foregroundStyle(.secondary)
                if last && !unmarked.isEmpty {
                    Text("Still to outline: \(unmarked.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Back") { markingIndex -= 1 }
                        .disabled(markingIndex == 0)
                    Spacer()
                    if last {
                        Button("Done") { withAnimation { mode = .organized } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!unmarked.isEmpty)
                    } else {
                        Button("Next") { markingIndex += 1 }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        } else {
            Text("Add shelves or drawers on the Plan screen first.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var tossStrip: some View {
        let toss = space.items.filter { $0.zone == Organizer.tossZone }.byName
        if !toss.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Toss First")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(toss) { item in
                            Image(uiImage: IconCatalog.image(name: item.name, className: item.className))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .accessibilityLabel(item.name)
                        }
                    }
                }
            }
        }
    }
}
