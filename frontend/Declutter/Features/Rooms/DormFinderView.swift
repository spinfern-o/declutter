import SwiftData
import SwiftUI

/// Pick your school and hall to get a room of the right size without outlining it.
/// The sizes come from the server's list (backend/data/dorms.json).
struct DormFinderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var dorms: [Dorm]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if let dorms {
                    let schools = Array(Set(dorms.map(\.school))).sorted()
                    ForEach(schools, id: \.self) { school in
                        Section(school) {
                            ForEach(dorms.indices.filter { dorms[$0].school == school }, id: \.self) { i in
                                Button {
                                    add(dorms[i])
                                } label: {
                                    LabeledContent(name(dorms[i]),
                                                   value: "\(Int(dorms[i].width_ft.rounded())) × \(Int(dorms[i].length_ft.rounded())) ft")
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if let dorms {
                    if dorms.isEmpty {
                        ContentUnavailableView("No Dorms Yet", systemImage: "building.2",
                                               description: Text("No dorm room sizes have been added yet. Use New Room to outline yours."))
                    }
                } else if failed {
                    ContentUnavailableView {
                        Label("Couldn't Load Dorms", systemImage: "wifi.slash")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Find My Dorm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func name(_ dorm: Dorm) -> String {
        dorm.room.map { "\(dorm.hall), \($0)" } ?? dorm.hall
    }

    private func add(_ dorm: Dorm) {
        context.insert(Room(name: name(dorm), corners: Furniture.corners(widthFeet: dorm.width_ft, lengthFeet: dorm.length_ft)))
        try? context.save()
        dismiss()
    }

    private func load() async {
        failed = false
        do { dorms = try await Catalog.dorms() } catch { failed = true }
    }
}
