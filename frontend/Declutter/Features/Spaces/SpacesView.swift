import PhotosUI
import SwiftData
import SwiftUI

struct SpacesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Space.createdAt, order: .reverse) private var spaces: [Space]
    @State private var path: [Space] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pending: Data?  // photo waiting on the server; kept so Retry doesn't lose it
    @State private var failed = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(spaces) { space in
                    NavigationLink(value: space) {
                        LabeledContent(space.name, value: "\(space.items.count) items")
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(spaces[i]) }
                    try? context.save()
                }
            }
            .overlay {
                if spaces.isEmpty {
                    ContentUnavailableView("No cabinets yet", systemImage: "cabinet",
                                           description: Text("Photograph a cabinet and Declutter sorts what's inside."))
                }
            }
            .overlay {
                if pending != nil && !failed {
                    ProgressView("Sorting…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .navigationTitle("Declutter")
            .navigationDestination(for: Space.self) { SpaceView(space: $0) }
            .toolbar {
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo", systemImage: "camera") { showCamera = true }
                    }
                    // a PhotosPicker inside a Menu is torn down with the menu, so drive it from a button
                    Button("Choose Photo", systemImage: "photo") { showLibrary = true }
                } label: {
                    Label("New cabinet", systemImage: "plus")
                }
                .disabled(pending != nil)
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) {
                guard let pickerItem else { return }
                self.pickerItem = nil
                Task {
                    // library photos can be HEIC, which the server can't read; re-encode as JPEG
                    if let data = try? await pickerItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data), let jpeg = API.jpeg(image) {
                        sort(jpeg)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let jpeg = API.jpeg(image) { sort(jpeg) }
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't sort this photo", isPresented: $failed) {
                Button("Retry") { if let pending { sort(pending) } }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("Check your connection and try again.")
            }
        }
    }

    private func sort(_ jpeg: Data) {
        pending = jpeg
        Task {
            do {
                let response = try await API.detect(jpeg: jpeg)
                let space = Space(name: "Cabinet \(spaces.count + 1)", photo: jpeg, zones: response.zones)
                context.insert(space)
                for found in response.items {
                    space.items.append(Item(name: found.class.replacingOccurrences(of: "_", with: " "),
                                            className: found.class, zone: found.zone, confidence: found.confidence,
                                            cutout: Data(base64Encoded: found.cutout), box: found.box))
                }
                try? context.save()
                pending = nil
                path.append(space)
            } catch {
                failed = true
            }
        }
    }
}
