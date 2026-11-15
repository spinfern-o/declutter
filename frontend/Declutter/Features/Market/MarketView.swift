import SwiftData
import SwiftUI

/// The marketplace: real furniture from real stores. Adding a piece puts it in the room at its real size;
/// the link opens its page at the store.
struct MarketView: View {
    let room: Room
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: Catalog.Products?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if let catalog {
                    Section {
                        ForEach(catalog.products) { row($0) }
                    } footer: {
                        Text("Prices were checked on \(catalog.checked). The store's page has today's price.")
                    }
                }
            }
            .overlay {
                if catalog == nil {
                    if failed {
                        ContentUnavailableView {
                            Label("Couldn't Load Furniture", systemImage: "wifi.slash")
                        } description: {
                            Text("Check your connection and try again.")
                        } actions: {
                            Button("Try Again") { Task { await load() } }
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Add Furniture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func row(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name).font(.headline)
            Text("\(product.store) · \(product.price, format: .currency(code: "USD")) · \(Furniture.label(sizeInches: product.size_in))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if product.kind == "storage" {
                Text("Storage: your items can be organized into it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Add to Room", systemImage: "plus") {
                    _ = Space.furniture(product, in: room, context: context)
                    dismiss()
                }
                Spacer()
                if let url = URL(string: product.url) {
                    Link("View at \(product.store)", destination: url)
                }
            }
            .buttonStyle(.borderless)  // two buttons in one row: each takes its own tap
        }
        .accessibilityElement(children: .contain)
    }

    private func load() async {
        failed = false
        do { catalog = try await Catalog.products() } catch { failed = true }
    }
}
