import SwiftUI
import AetherCore
import AetherUI

@MainActor
struct GlobalContentSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var vodStreams: [XstreamVOD] = []
    @State private var series: [XstreamSeries] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let xstreamService: XstreamService
    
    init(xstreamService: XstreamService) {
        self.xstreamService = xstreamService
    }
    
    var filteredContent: [(id: String, title: String, type: ContentType, item: Any)] {
        let query = searchText.lowercased()
        var results: [(id: String, title: String, type: ContentType, item: Any)] = []
        
        if query.isEmpty {
            return results
        }
        
        // Filter VOD
        for stream in vodStreams where stream.name.lowercased().contains(query) {
            results.append((
                id: "vod_\(stream.streamID)",
                title: stream.name,
                type: .movie,
                item: stream
            ))
        }
        
        // Filter Series
        for s in series where s.name.lowercased().contains(query) {
            results.append((
                id: "series_\(s.seriesID)",
                title: s.name,
                type: .series,
                item: s
            ))
        }
        
        return results.prefix(100).map { $0 }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.aetherText.opacity(0.6))
                
                TextField("Search movies and series...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.aetherText)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.aetherText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.aetherBackground.opacity(0.8))
            
            Divider()
            
            // Results
            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.aetherError)
                    Text(error)
                        .foregroundStyle(Color.aetherText)
                }
                Spacer()
            } else if searchText.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.aetherText.opacity(0.3))
                    Text("Type to search across all content")
                        .foregroundStyle(Color.aetherText.opacity(0.6))
                }
                Spacer()
            } else if filteredContent.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.aetherText.opacity(0.3))
                    Text("No results found")
                        .foregroundStyle(Color.aetherText.opacity(0.6))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredContent, id: \.id) { item in
                            ContentCard(
                                title: item.title,
                                type: item.type,
                                action: {
                                    handleSelection(item)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.aetherBackground)
        .task {
            await loadAllContent()
        }
    }
    
    private func loadAllContent() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let vodTask = xstreamService.vodStreams(categoryID: nil)
            async let seriesTask = xstreamService.seriesList(categoryID: nil)
            
            let (vodResult, seriesResult) = try await (vodTask, seriesTask)
            
            vodStreams = vodResult
            series = seriesResult
        } catch {
            errorMessage = "Failed to load content: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func handleSelection(_ item: (id: String, title: String, type: ContentType, item: Any)) {
        // TODO: Implement navigation to player or detail view
        dismiss()
    }
}

enum ContentType {
    case movie
    case series
}

struct ContentCard: View {
    let title: String
    let type: ContentType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.aetherSecondary.opacity(0.3))
                        .aspectRatio(2/3, contentMode: .fit)
                    
                    Image(systemName: type == .movie ? "film" : "tv")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.aetherText.opacity(0.5))
                }
                .frame(height: 180)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.aetherCaption)
                        .foregroundStyle(Color.aetherText)
                        .lineLimit(2)
                    
                    Text(type == .movie ? "Movie" : "Series")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.aetherText.opacity(0.6))
                }
            }
            .padding(8)
        }
        .buttonStyle(.plain)
        .background(Color.aetherSecondary.opacity(0.2))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.aetherPrimary.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    GlobalContentSearchView(
        xstreamService: XstreamService(
            credentials: XstreamCredentials(
                baseURL: URL(string: "http://example.com")!,
                username: "test",
                password: "test"
            )
        )
    )
}
