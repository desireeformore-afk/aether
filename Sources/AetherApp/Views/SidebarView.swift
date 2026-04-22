import SwiftUI
import AetherCore

// MARK: - SidebarItem

enum SidebarItem: String, CaseIterable, Hashable {
    case home      = "Główna"
    case vod       = "Filmy"
    case series    = "Seriale"
    case live      = "Na żywo"
    case search    = "Szukaj"
    case favorites = "Ulubione"
    case history   = "Historia"
    case settings  = "Ustawienia"

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .vod:       return "film.fill"
        case .series:    return "tv.fill"
        case .live:      return "antenna.radiowaves.left.and.right"
        case .search:    return "magnifyingglass"
        case .favorites: return "star.fill"
        case .history:   return "clock.arrow.circlepath"
        case .settings:  return "gearshape.fill"
        }
    }
}

// MARK: - SidebarRowView

private struct SidebarRowView: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private let activeGradientStart = Color(red: 0.20, green: 0.12, blue: 0.55)
    private let activeGradientEnd   = Color(red: 0.10, green: 0.08, blue: 0.35)
    private let accentColor         = Color(red: 0.55, green: 0.35, blue: 1.0)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Active left border accent
                Rectangle()
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(width: 3)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                // Icon container
                ZStack {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.45))
                        .shadow(color: isSelected ? accentColor.opacity(0.8) : .clear, radius: 4)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
                .frame(width: 28, height: 28)

                // Label
                Text(item.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                Spacer()
            }
            .padding(.leading, 0)
            .padding(.trailing, 12)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [activeGradientStart, activeGradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.leading, 3) // offset so gradient starts after accent bar
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .padding(.leading, 3)
                        .animation(.easeInOut(duration: 0.1), value: isHovered)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - SidebarSectionHeader

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white.opacity(0.25))
                .tracking(2)
                .textCase(.uppercase)
                .padding(.leading, 15)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - SidebarDivider

private struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

// MARK: - SidebarView

@MainActor
struct SidebarView: View {
    @Binding var selection: SidebarItem
    let playlistName: String?

    private let sidebarBg = Color(red: 0.05, green: 0.05, blue: 0.07)
    private let accentPurple = Color(red: 0.55, green: 0.35, blue: 1.0)

    private let mainItems: [SidebarItem] = [.home, .vod, .series, .live, .search, .favorites, .history]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            // Main nav items
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(mainItems, id: \.self) { item in
                        SidebarRowView(item: item, isSelected: selection == item) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selection = item
                            }
                        }
                    }

                    SidebarDivider()
                        .padding(.vertical, 8)

                    SidebarSectionHeader(title: "Biblioteka")

                    // Settings at bottom of library section
                    SidebarRowView(item: .settings, isSelected: selection == .settings) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = .settings
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sidebarBg)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(accentPurple)

            VStack(alignment: .leading, spacing: 1) {
                Text("AETHER")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .tracking(3)

                Text(playlistName ?? "IPTV")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}
