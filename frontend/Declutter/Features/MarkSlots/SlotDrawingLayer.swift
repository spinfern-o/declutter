import SwiftData
import SwiftUI

/// Marking mode: drag across the photo to outline the current slot. Other outlined slots stay visible.
struct SlotDrawingLayer: View {
    @Bindable var space: Space
    let size: CGSize  // the photo as displayed
    let slot: String
    @State private var draft: CGRect?  // in screen points, while dragging

    var body: some View {
        ZStack(alignment: .topLeading) {
            SlotOutlines(rects: space.slotRects, size: size, highlight: slot)
            if let draft {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: draft.width, height: draft.height)
                    .offset(x: draft.minX, y: draft.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = value.startLocation, end = value.location
                    draft = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                   width: abs(end.x - start.x), height: abs(end.y - start.y))
                        .intersection(CGRect(origin: .zero, size: size))
                }
                .onEnded { _ in
                    if let draft, draft.width > 12, draft.height > 12 {  // ignore taps and slips
                        space.slotRects[slot] = [draft.minX / size.width, draft.minY / size.height,
                                                 draft.width / size.width, draft.height / size.height]
                        try? space.modelContext?.save()
                    }
                    draft = nil
                }
        )
        .accessibilityLabel("Drag to outline \(slot)")
    }
}

/// A dashed outline with its name for each marked slot.
struct SlotOutlines: View {
    let rects: [String: [Double]]
    let size: CGSize
    var highlight: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rects.keys.sorted(), id: \.self) { slot in
                if let v = rects[slot], v.count == 4 {
                    let current = slot == highlight
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(current ? Color.accentColor : .white,
                                style: StrokeStyle(lineWidth: current ? 3 : 1.5, dash: [6, 4]))
                        .shadow(color: .black.opacity(0.6), radius: 1)  // keeps white dashes visible on light photos
                        .frame(width: v[2] * size.width, height: v[3] * size.height)
                        .overlay(alignment: .topLeading) {
                            Text(slot)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: .capsule)
                                .fixedSize()
                                .alignmentGuide(.top) { $0[.bottom] + 2 }  // sits just above the outline, so it never covers the items inside
                        }
                        .offset(x: v[0] * size.width, y: v[1] * size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
