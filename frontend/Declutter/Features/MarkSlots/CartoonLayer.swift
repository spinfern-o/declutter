import SwiftData
import SwiftUI

/// One cartoon per item on the photo: in its slot when organized, back over the real item (and faded
/// out) when showing the original. Dragging a cartoon moves its whole zone, like on the Plan screen.
struct CartoonLayer: View {
    @Bindable var space: Space
    let size: CGSize  // the photo as displayed
    let organized: Bool
    @State private var drag: (zone: String, offset: CGSize)?
    @State private var moves = 0  // haptic trigger

    private var ratio: Double { size.height / size.width }

    var body: some View {
        let items = space.items.filter { $0.zone != Organizer.tossZone }
        let targets = PhotoLayout.positions(
            items: items.map { (id: $0.persistentModelID, zone: $0.zone, name: $0.name, box: $0.box) },
            placement: space.placement, slotRects: space.slotRects, heightRatio: ratio)

        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                if let target = targets[item.persistentModelID] {
                    // items with no box (manual, saved earlier) have no "before" spot, so they just fade
                    cartoon(item, at: organized ? target : PhotoLayout.original(item.box, heightRatio: ratio) ?? target)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(.named("photo"))
        .sensoryFeedback(.success, trigger: moves)
    }

    private func cartoon(_ item: Item, at frame: CGRect) -> some View {
        let width = size.width  // layout space is in photo widths
        let slot = space.placement[item.zone] ?? ""
        let others = space.slots.filter { $0 != slot && space.slotRects[$0] != nil }
        let dragging = drag?.zone == item.zone

        return Image(uiImage: IconCatalog.image(name: item.name, className: item.className))
            .resizable()
            .scaledToFit()
            .frame(width: frame.width * width, height: frame.height * width)
            .scaleEffect(dragging ? 1.15 : 1)
            .opacity(organized ? 1 : 0)
            .allowsHitTesting(organized)
            .gesture(
                DragGesture(coordinateSpace: .named("photo"))
                    .onChanged { drag = (item.zone, $0.translation) }
                    .onEnded { value in
                        let point = CGPoint(x: value.location.x / width, y: value.location.y / width)
                        let target = PhotoLayout.slot(at: point, in: space.slotRects, heightRatio: ratio)
                        withAnimation(.spring) {
                            if let target, target != slot {
                                space.place(item.zone, in: target)
                                moves += 1
                            }
                            drag = nil  // a drop outside every slot springs back
                        }
                    }
            )
            .accessibilityLabel("\(item.name), in \(slot)")
            .accessibilityActions {
                ForEach(others, id: \.self) { target in
                    Button("Move to \(target)") {
                        withAnimation(.spring) { space.place(item.zone, in: target) }
                    }
                }
            }
            .offset(dragging ? drag!.offset : .zero)
            .position(x: frame.midX * width, y: frame.midY * width)
    }
}
