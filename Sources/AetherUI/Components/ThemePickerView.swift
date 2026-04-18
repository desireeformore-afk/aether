import SwiftUI
import AetherCore

/// Picker for selecting a visual theme.
public struct ThemePickerView: View {
    @EnvironmentObject private var themeService: ThemeService
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Motyw")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(themeService.allThemes) { theme in
                    ThemeCard(theme: theme, isSelected: theme.id == themeService.active.id)
                        .onTapGesture {
                            themeService.select(theme)
                        }
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: ThemeDefinition
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.accentColor)
                .frame(height: 60)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
            
            Text(theme.name)
                .font(.caption)
                .foregroundStyle(isSelected ? theme.accentColor : .secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? theme.accentColor : .clear, lineWidth: 2)
                )
        )
    }
}
