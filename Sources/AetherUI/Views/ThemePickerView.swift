import SwiftUI
import AetherCore

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

/// Grid of theme cards. Tapping selects a theme.
/// On macOS/iOS also shows a custom gradient builder section.
public struct ThemePickerView: View {
    @EnvironmentObject private var themeService: ThemeService

    // Custom gradient state (macOS/iOS only)
    #if !os(tvOS)
    @State private var customStart: Color = .purple
    @State private var customMid: Color? = nil
    @State private var customEnd: Color = .orange
    @State private var gradientDirection: GradientDirection = .topToBottom
    @State private var showMidStop: Bool = false
    @State private var gradientName: String = "My Gradient"
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

                // MARK: Custom gradient builder (not tvOS)
                #if !os(tvOS)
                Divider()

                GradientBuilderSection(
                    customStart: $customStart,
                    customMid: $customMid,
                    customEnd: $customEnd,
                    gradientDirection: $gradientDirection,
                    showMidStop: $showMidStop,
                    gradientName: $gradientName,
                    onApply: applyCustomGradient
                )
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
        var colors   = [startHex]
        if showMidStop, let mid = customMid {
            colors.append(mid.toHex() ?? "#FF6060")
        }
        colors.append(endHex)

        let custom = ThemeDefinition(
            id: "custom_gradient",
            name: gradientName.isEmpty ? "Custom" : gradientName,
            accentHex: startHex,
            background: .gradient(
                colors: colors,
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

// MARK: - Gradient Builder Section

#if !os(tvOS)
private struct GradientBuilderSection: View {
    @Binding var customStart: Color
    @Binding var customMid: Color?
    @Binding var customEnd: Color
    @Binding var gradientDirection: GradientDirection
    @Binding var showMidStop: Bool
    @Binding var gradientName: String
    let onApply: () -> Void

    @State private var midColor: Color = .red

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Gradient")
                .font(.headline)

            // Live preview
            GradientPreviewBar(
                start: customStart,
                mid: showMidStop ? midColor : nil,
                end: customEnd,
                direction: gradientDirection
            )
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            // Color stops row
            VStack(alignment: .leading, spacing: 8) {
                Text("Color Stops")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    colorStop(label: "Start", color: $customStart)

                    // Mid stop toggle
                    VStack(spacing: 4) {
                        Button {
                            showMidStop.toggle()
                            if showMidStop { customMid = midColor }
                            else { customMid = nil }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                        .foregroundStyle(showMidStop ? Color.aetherPrimary : .secondary)
                                        .frame(width: 30, height: 30)
                                    if showMidStop {
                                        Circle()
                                            .fill(midColor)
                                            .frame(width: 22, height: 22)
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text("Mid")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showMidStop {
                            ColorPicker("", selection: Binding(
                                get: { midColor },
                                set: { midColor = $0; customMid = $0 }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 30)
                        }
                    }

                    colorStop(label: "End", color: $customEnd)

                    Spacer()

                    // Direction picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Direction").font(.caption).foregroundStyle(.secondary)
                        Picker("Direction", selection: $gradientDirection) {
                            ForEach(GradientDirection.allCases, id: \.self) { dir in
                                Text(dir.label).tag(dir)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(minWidth: 120)
                    }
                }
            }

            // Name field + Apply button
            HStack(spacing: 12) {
                TextField("Gradient name…", text: $gradientName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Button(action: onApply) {
                    Label("Apply", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Color.aetherPrimary)
            }
        }
    }

    private func colorStop(label: String, color: Binding<Color>) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30, height: 30)
        }
    }
}

// MARK: - Gradient Preview Bar

private struct GradientPreviewBar: View {
    let start: Color
    let mid: Color?
    let end: Color
    let direction: GradientDirection

    var body: some View {
        let stops: [Gradient.Stop]
        if let mid {
            stops = [
                .init(color: start, location: 0),
                .init(color: mid, location: 0.5),
                .init(color: end, location: 1),
            ]
        } else {
            stops = [
                .init(color: start, location: 0),
                .init(color: end, location: 1),
            ]
        }
        return LinearGradient(
            stops: stops,
            startPoint: direction.unitPoint.start,
            endPoint: direction.unitPoint.end
        )
    }
}
#endif

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
                    .fill(Color(hex: theme.accentHex) ?? .accentColor)
                    .frame(width: 24, height: 24)
            }

            Text(theme.name)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .padding(8)
        .overlay(
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
    var unitPoint: (start: UnitPoint, end: UnitPoint) {
        switch self {
        case .topToBottom: return (.top, .bottom)
        case .leadingToTrailing: return (.leading, .trailing)
        case .diagonal: return (.topLeading, .bottomTrailing)
        }
    }
}

// MARK: - Color → hex helper

private extension Color {
    func toHex() -> String? {
        #if os(macOS)
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
        #endif
    }
}
#endif
