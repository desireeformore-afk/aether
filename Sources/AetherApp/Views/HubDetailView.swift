import SwiftUI
import AetherCore

struct HubDetailView: View {
    let hub: BrandHub
    let shelves: [(title: String, items: [ShelfItem])]
    let credentials: XstreamCredentials
    let onBack: () -> Void
    var onSelectVODItem: (ShelfItem) -> Void
    var onSelectSeries: (XstreamSeries) -> Void
    
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var animation
    
    init(hub: BrandHub, shelves: [(title: String, items: [ShelfItem])], credentials: XstreamCredentials, onBack: @escaping () -> Void, onSelectVODItem: @escaping (ShelfItem) -> Void, onSelectSeries: @escaping (XstreamSeries) -> Void) {
        self.hub = hub
        self.shelves = shelves
        self.credentials = credentials
        self.onBack = onBack
        self.onSelectVODItem = onSelectVODItem
        self.onSelectSeries = onSelectSeries
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()
            
            // Brand hero gradient
            LinearGradient(
                colors: [hub.themeColor.opacity(0.4), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 400)
            .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Area
                    VStack(spacing: 16) {
                        Image(systemName: hub.systemImage)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(hub.themeColor)
                            .shadow(color: hub.themeColor.opacity(0.5), radius: 20)
                            .padding(.top, 60)
                        
                        Text(hub.rawValue)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 20)
                    
                    if shelves.isEmpty {
                        Text("No content available in this section.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelf in
                            CategoryShelf(
                                title: shelf.title,
                                items: shelfItemsWithTap(shelf.items)
                            )
                        }
                    }
                    
                    Spacer(minLength: 60)
                }
            }
            
            // Custom Navigation Bar
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Home")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding()
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        // or a simpler transition if preferred
    }
    
    private func shelfItemsWithTap(_ items: [ShelfItem]) -> [ShelfItem] {
        items.map { item in
            if let vod = item.vod {
                return ShelfItem(
                    id: item.id,
                    title: item.title,
                    imageURL: item.imageURL,
                    vod: vod,
                    series: nil,
                    tags: item.tags,
                    alternateVODs: item.alternateVODs,
                    onTap: { onSelectVODItem(item) }
                )
            } else if let series = item.series {
                return ShelfItem(
                    id: item.id,
                    title: item.title,
                    imageURL: item.imageURL,
                    vod: nil,
                    series: series,
                    onTap: { onSelectSeries(series) }
                )
            }
            return item
        }
    }
}
