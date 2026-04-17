import SwiftUI
import AetherCore

/// Grid of theme cards. Tapping selects a theme.
/// On macOS/iOS also shows a custom gradient builder section.
public struct ThemePickerView: View {
    @EnvironmentObject private var themeService: ThemeService

    // Custom gradient state (macOS/iOS only)
    #if !os(tvOS)
    @State private var customStart: Color = .purple
    @State private var customEnd: Color = .orange
    @State private var gradientDirection: GradientDirection = .topToBottom
    #endif

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Built-in themes grid
                Text("Themes")
                    .font(.title2).bold()
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ThemeDefinition.allBuiltIn) { theme in
                        ThemeCard(theme: theme, isSelected: themeService.active.id == theme.id)
                            .onTapGesture { themeService.select(theme) }
                            #if os(tvOS)
                            .focusable()
                            #endif
                    }
                }
                .padding(.horizontal)

                // MARK: Custom gradient (not tvOS)
                #if !os(tvOS)
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Gradient")
                        .font(.headline)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start").font(.caption).foregroundStyle(.secondary)
                            ColorPicker("", selection: $customStart, supportsOpacity: false)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("End").font(.caption).foregroundStyle(.secondary)
                            ColorPicker("", selection: $customEnd, supportsOpacity: false)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Direction").font(.caption).foregroundStyle(.secondary)
                            Picker("Direction", selection: $gradientDirection) {
                                ForEach(GradientDirection.allCases, id: \.self) { dir in
                                    Text(dir.label).tag(dir)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minWidth: 160)
                        }
                    }

                    Button("Apply Custom Gradient") {
                        applyCustomGradient()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                #endif
            }
            .padding(.vertical)
        }
    }

    #if !os(tvOS)
    private func applyCustomGradient() {
        let startHex = customStart.toHex() ?? "#7B61FF"
        let endHex   = customEnd.toHex()   ?? "#FF9F0A"
        let custom = ThemeDefinition(
            id: "custom_gradient",
            name: "Custom",
            accentHex: startHex,
            background: .gradient(
                colors: [startHex, endHex],
                startPoint: gradientDirection.startPoint,
                endPoint: gradientDirection.endPoint
            ),
            surfaceHex: "#1C1C1E",
            textHex: "#FFFFFF"
        )
        themeService.select(custom)
    }
    #endif
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: ThemeDefinition
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                theme.backgroundView()
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: theme.accentHex))
                    .frame(width: 24, height: 24)
            }

            Text(theme.name)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Gradient Direction

#if !os(tvOS)
private enum GradientDirection: String, CaseIterable {
    case topToBottom, leadingToTrailing, diagonal

    var label: String {
        switch self {
        case .topToBottom: return "↓"
        case .leadingToTrailing: return "→"
        case .diagonal: return "↘"
        }
    }
    var startPoint: String {
        switch self {
        case .topToBottom: return "top"
        case .leadingToTrailing: return "leading"
        case .diagonal: return "topLeading"
        }
    }
    var endPoint: String {
        switch self {
        case .topToBottom: return "bottom"
        case .leadingToTrailing: return "trailing"
        case .diagonal: return "bottomLeading"
        }
    }
}

// MARK: - Color → hex helper

private extension Color {
    func toHex() -> String? {
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        #else
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let rInt = Int(r * 255), gInt = Int(g * 255), bInt = Int(b * 255)
        let (r, g, b) = (rInt, gInt, bInt)
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
