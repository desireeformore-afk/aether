     1|#if os(macOS)
     2|import SwiftUI
     3|import AetherCore
     4|
     5|// MARK: - CommandPaletteView
     6|
     7|/// ⌘K command palette — fuzzy-searches channels and playlists.
     8|/// macOS only. Dismiss with Escape or by clicking outside.
     9|struct CommandPaletteView: View {
    10|    @Binding var isPresented: Bool
    11|    @Bindable var player: PlayerCore
    12|
    13|    /// All channels across all loaded playlists.
    14|    let channels: [Channel]
    15|
    16|    @State private var query: String = ""
    17|    @State private var selectedIndex: Int = 0
    18|    @FocusState private var searchFocused: Bool
    19|
    20|    private var results: [Channel] {
    21|        guard !query.isEmpty else { return Array(channels.prefix(12)) }
    22|        return channels
    23|            .filter { $0.name.localizedCaseInsensitiveContains(query) }
    24|            .prefix(12)
    25|            .map { $0 }
    26|    }
    27|
    28|    var body: some View {
    29|        VStack(spacing: 0) {
    30|            // Search bar
    31|            HStack(spacing: 10) {
    32|                Image(systemName: "magnifyingglass")
    33|                    .foregroundStyle(.secondary)
    34|                TextField("Search channels…", text: $query)
    35|                    .textFieldStyle(.plain)
    36|                    .font(.system(size: 16))
    37|                    .focused($searchFocused)
    38|                    .onKeyPress(.escape) {
    39|                        isPresented = false
    40|                        return .handled
    41|                    }
    42|                    .onKeyPress(.upArrow) {
    43|                        selectedIndex = max(0, selectedIndex - 1)
    44|                        return .handled
    45|                    }
    46|                    .onKeyPress(.downArrow) {
    47|                        selectedIndex = min(results.count - 1, selectedIndex + 1)
    48|                        return .handled
    49|                    }
    50|                    .onKeyPress(.return) {
    51|                        commitSelection()
    52|                        return .handled
    53|                    }
    54|                if !query.isEmpty {
    55|                    Button { query = "" } label: {
    56|                        Image(systemName: "xmark.circle.fill")
    57|                            .foregroundStyle(.secondary)
    58|                    }
    59|                    .buttonStyle(.plain)
    60|                }
    61|            }
    62|            .padding(.horizontal, 16)
    63|            .padding(.vertical, 12)
    64|
    65|            Divider()
    66|
    67|            // Results list
    68|            if results.isEmpty {
    69|                Text("No channels found")
    70|                    .font(.callout)
    71|                    .foregroundStyle(.secondary)
    72|                    .frame(maxWidth: .infinity, minHeight: 80)
    73|            } else {
    74|                ScrollViewReader { proxy in
    75|                    ScrollView {
    76|                        LazyVStack(spacing: 0) {
    77|                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, channel in
    78|                                CommandPaletteRow(
    79|                                    channel: channel,
    80|                                    isSelected: idx == selectedIndex,
    81|                                    isPlaying: player.currentChannel == channel
    82|                                )
    83|                                .id(idx)
    84|                                .onTapGesture {
    85|                                    selectedIndex = idx
    86|                                    commitSelection()
    87|                                }
    88|                            }
    89|                        }
    90|                        .padding(.vertical, 4)
    91|                    }
    92|                    .onChange(of: selectedIndex) { _, newIdx in
    93|                        withAnimation(.easeInOut(duration: 0.1)) {
    94|                            proxy.scrollTo(newIdx, anchor: .center)
    95|                        }
    96|                    }
    97|                }
    98|                .frame(maxHeight: 320)
    99|            }
   100|
   101|            Divider()
   102|
   103|            // Footer hint
   104|            HStack(spacing: 16) {
   105|                Label("Select", systemImage: "return")
   106|                Label("Navigate", systemImage: "arrow.up.arrow.down")
   107|                Label("Dismiss", systemImage: "escape")
   108|            }
   109|            .font(.system(size: 10))
   110|            .foregroundStyle(.tertiary)
   111|            .padding(.horizontal, 16)
   112|            .padding(.vertical, 8)
   113|        }
   114|        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
   115|        .frame(width: 480)
   116|        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
   117|        .onAppear {
   118|            searchFocused = true
   119|            selectedIndex = 0
   120|        }
   121|        .onChange(of: query) { _, _ in
   122|            selectedIndex = 0
   123|        }
   124|    }
   125|
   126|    private func commitSelection() {
   127|        guard !results.isEmpty, results.indices.contains(selectedIndex) else { return }
   128|        let channel = results[selectedIndex]
   129|        isPresented = false
   130|        Task { @MainActor in
   131|            player.channelList = channels
   132|            player.play(channel)
   133|        }
   134|    }
   135|}
   136|
   137|// MARK: - CommandPaletteRow
   138|
   139|private struct CommandPaletteRow: View {
   140|    let channel: Channel
   141|    let isSelected: Bool
   142|    let isPlaying: Bool
   143|
   144|    var body: some View {
   145|        HStack(spacing: 10) {
   146|            AsyncImage(url: channel.logoURL) { image in
   147|                image.resizable().scaledToFit()
   148|            } placeholder: {
   149|                Image(systemName: "tv")
   150|                    .foregroundStyle(.secondary)
   151|            }
   152|            .frame(width: 28, height: 28)
   153|            .clipShape(RoundedRectangle(cornerRadius: 5))
   154|
   155|            VStack(alignment: .leading, spacing: 1) {
   156|                Text(channel.name)
   157|                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
   158|                    .lineLimit(1)
   159|                if !channel.groupTitle.isEmpty {
   160|                    Text(channel.groupTitle)
   161|                        .font(.system(size: 10))
   162|                        .foregroundStyle(.secondary)
   163|                        .lineLimit(1)
   164|                }
   165|            }
   166|
   167|            Spacer()
   168|
   169|            if isPlaying {
   170|                Image(systemName: "waveform")
   171|                    .font(.system(size: 11))
   172|                    .foregroundStyle(Color.aetherAccent)
   173|                    .symbolEffect(.variableColor.iterative)
   174|            }
   175|        }
   176|        .padding(.horizontal, 14)
   177|        .padding(.vertical, 6)
   178|        .background(
   179|            isSelected
   180|                ? Color.aetherAccent.opacity(0.15)
   181|                : Color.clear,
   182|            in: RoundedRectangle(cornerRadius: 6)
   183|        )
   184|        .padding(.horizontal, 4)
   185|        .contentShape(Rectangle())
   186|    }
   187|}
   188|#endif
   189|