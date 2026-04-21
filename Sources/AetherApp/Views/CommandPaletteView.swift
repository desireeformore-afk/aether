#if os(macOS)
import SwiftUI
import AetherCore

// MARK: - CommandPaletteView

/// ⌘K command palette — fuzzy-searches channels and playlists.
/// macOS only. Dismiss with Escape or by clicking outside.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Bindable var player: PlayerCore

    /// All channels across all loaded playlists.
    let channels: [Channel]

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    private var results: [Channel] {
        guard !query.isEmpty else { return Array(channels.prefix(12)) }
        return channels
            .filter { fuzzyScore(query, in: $0.name) > 0 }
            .sorted { fuzzyScore(query, in: $0.name) > fuzzyScore(query, in: $1.name) }
            .prefix(12)
            .map { $0 }
    }

    private func fuzzyScore(_ query: String, in text: String) -> Int {
        let q = query.lowercased()
        let t = text.lowercased()
        if t.contains(q) { return 100 }
        var qi = q.startIndex
        var score = 0
        for ch in t {
            if qi < q.endIndex && ch == q[qi] {
                score += 1
                qi = q.index(after: qi)
            }
        }
        return qi == q.endIndex ? score : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search channels…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                    .onKeyPress(.escape) {
                        isPresented = false
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selectedIndex = max(0, selectedIndex - 1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        selectedIndex = min(results.count - 1, selectedIndex + 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        commitSelection()
                        return .handled
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results list
            if results.isEmpty {
                Text("No channels found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, channel in
                                CommandPaletteRow(
                                    channel: channel,
                                    isSelected: idx == selectedIndex,
                                    isPlaying: player.currentChannel == channel
                                )
                                .id(idx)
                                .onTapGesture {
                                    selectedIndex = idx
                                    commitSelection()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { _, newIdx in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            // Footer hint
            HStack(spacing: 16) {
                Label("Select", systemImage: "return")
                Label("Navigate", systemImage: "arrow.up.arrow.down")
                Label("Dismiss", systemImage: "escape")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 480)
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear {
            searchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private func commitSelection() {
        guard !results.isEmpty, results.indices.contains(selectedIndex) else { return }
        let channel = results[selectedIndex]
        isPresented = false
        Task { @MainActor in
            player.channelList = channels
            player.play(channel)
        }
    }
}

// MARK: - CommandPaletteRow

private struct CommandPaletteRow: View {
    let channel: Channel
    let isSelected: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: channel.logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "tv")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if !channel.groupTitle.isEmpty {
                    Text(channel.groupTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.aetherAccent)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color.aetherAccent.opacity(0.15)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
#endif
