import SwiftData
import SwiftUI

struct SpaceView: View {
    @Bindable var space: Space
    @Environment(\.modelContext) private var context
    @State private var adding = false
    @State private var organizing = false
    @State private var renaming: Item?
    @State private var newName = ""

    /// Zones that have items, in the server's order (plus any stray zone, so no item can vanish).
    private var shownZones: [String] {
        var seen = Set<String>()
        return (space.zones + space.items.map(\.zone))
            .filter { seen.insert($0).inserted }
            .filter { zone in space.items.contains { $0.zone == zone } }
    }

    var body: some View {
        List {
            if let photo = UIImage(data: space.photo) {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityLabel("Photo of \(space.name)")
                }
            }
            if space.items.isEmpty {
                Text("No items found. Tap + to add one.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shownZones, id: \.self) { zone in
                Section(zone) {
                    ForEach(space.items.filter { $0.zone == zone }.byName) { item in
                        ItemRow(item: item)
                            .contextMenu {
                                Menu("Move to", systemImage: "arrow.right") {
                                    ForEach(space.zones.filter { $0 != zone }, id: \.self) { target in
                                        Button(target) {
                                            item.zone = target
                                            try? context.save()
                                        }
                                    }
                                }
                                Button("Rename", systemImage: "pencil") {
                                    newName = item.name
                                    renaming = item
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                            }
                    }
                }
            }
        }
        .navigationTitle(space.name)
        .toolbar {
            Button("Add item", systemImage: "plus") { adding = true }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                organizing = true
            } label: {
                Label("Organize", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .disabled(space.items.isEmpty)
        }
        .navigationDestination(isPresented: $organizing) { CabinetSceneView(space: space) }
        .sheet(isPresented: $adding) { AddItemSheet(space: space) }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    renaming?.name = name
                    try? context.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func delete(_ item: Item) {
        space.items.removeAll { $0 == item }
        context.delete(item)
        try? context.save()  // autosave is debounced; an app killed right after would bring the item back
    }
}
