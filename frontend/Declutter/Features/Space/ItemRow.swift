import SwiftUI

struct ItemRow: View {
    let item: Item
    @ScaledMetric private var thumb = 44.0  // grows with Dynamic Type like the text beside it

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = item.cutout, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().padding(4)
                } else {
                    Image(systemName: "shippingbox").foregroundStyle(.secondary)
                }
            }
            .frame(width: thumb, height: thumb)
            // a neutral tile keeps black items visible in dark mode and white ones in light mode
            .background(.fill.tertiary, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
            Text(item.name)
        }
    }
}
