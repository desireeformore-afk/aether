import SwiftUI
import AetherCore

/// Subtitle styling settings view.
public struct SubtitleStylingView: View {
    @ObservedObject var settings: SubtitleStylingSettings
    @Environment(\.dismiss) private var dismiss

    public init(settings: SubtitleStylingSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Subtitle Styling")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Reset") {
                    settings.reset()
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Font settings
                    GroupBox("Font") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Font Family", selection: $settings.fontFamily) {
                                ForEach(SubtitleFont.allCases, id: \.self) { font in
                                    Text(font.displayName).tag(font)
                                }
                            }

                            HStack {
                                Text("Font Size")
                                Spacer()
                                Slider(value: $settings.fontSize, in: 12...48, step: 2)
                                    .frame(width: 200)
                                Text("\(Int(settings.fontSize))pt")
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }

                            Toggle("Bold", isOn: $settings.isBold)
                            Toggle("Italic", isOn: $settings.isItalic)
                        }
                    }

                    // Color settings
                    GroupBox("Colors") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Text Color")
                                Spacer()
                                ColorPicker("", selection: $settings.textColor)
                            }

                            HStack {
                                Text("Background Color")
                                Spacer()
                                ColorPicker("", selection: $settings.backgroundColor)
                            }

                            HStack {
                                Text("Background Opacity")
                                Spacer()
                                Slider(value: $settings.backgroundOpacity, in: 0...1)
                                    .frame(width: 200)
                                Text("\(Int(settings.backgroundOpacity * 100))%")
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Outline settings
                    GroupBox("Outline") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Outline", isOn: $settings.hasOutline)

                            if settings.hasOutline {
                                HStack {
                                    Text("Outline Color")
                                    Spacer()
                                    ColorPicker("", selection: $settings.outlineColor)
                                }

                                HStack {
                                    Text("Outline Width")
                                    Spacer()
                                    Slider(value: $settings.outlineWidth, in: 0...5, step: 0.5)
                                        .frame(width: 200)
                                    Text("\(String(format: "%.1f", settings.outlineWidth))pt")
                                        .frame(width: 40, alignment: .trailing)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Position settings
                    GroupBox("Position") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Vertical Position", selection: $settings.verticalPosition) {
                                ForEach(SubtitlePosition.allCases, id: \.self) { pos in
                                    Text(pos.displayName).tag(pos)
                                }
                            }

                            HStack {
                                Text("Bottom Margin")
                                Spacer()
                                Slider(value: $settings.bottomMargin, in: 0...200, step: 10)
                                    .frame(width: 200)
                                Text("\(Int(settings.bottomMargin))px")
                                    .frame(width: 50, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Preview
                    GroupBox("Preview") {
                        VStack {
                            ZStack {
                                Color.black
                                    .frame(height: 150)

                                Text("Sample subtitle text")
                                    .font(.system(size: settings.fontSize, weight: settings.isBold ? .bold : .regular))
                                    .italic(settings.isItalic)
                                    .foregroundStyle(settings.textColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        settings.backgroundColor.opacity(settings.backgroundOpacity)
                                    )
                                    .overlay(
                                        settings.hasOutline ?
                                        Text("Sample subtitle text")
                                            .font(.system(size: settings.fontSize, weight: settings.isBold ? .bold : .regular))
                                            .italic(settings.isItalic)
                                            .foregroundStyle(.clear)
                                            .background(
                                                Text("Sample subtitle text")
                                                    .font(.system(size: settings.fontSize, weight: settings.isBold ? .bold : .regular))
                                                    .italic(settings.isItalic)
                                                    .foregroundStyle(settings.outlineColor)
                                                    .blur(radius: settings.outlineWidth)
                                            )
                                        : nil
                                    )
                                    .padding(.bottom, settings.bottomMargin)
                                    .frame(maxHeight: .infinity, alignment: settings.verticalPosition == .bottom ? .bottom : .top)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}

/// Subtitle styling settings.
@MainActor
public final class SubtitleStylingSettings: ObservableObject {
    @Published public var fontFamily: SubtitleFont = .system
    @Published public var fontSize: Double = 20
    @Published public var isBold: Bool = false
    @Published public var isItalic: Bool = false
    @Published public var textColor: Color = .white
    @Published public var backgroundColor: Color = .black
    @Published public var backgroundOpacity: Double = 0.7
    @Published public var hasOutline: Bool = true
    @Published public var outlineColor: Color = .black
    @Published public var outlineWidth: Double = 2
    @Published public var verticalPosition: SubtitlePosition = .bottom
    @Published public var bottomMargin: Double = 60

    private let userDefaults: UserDefaults
    private let settingsKey = "aether.subtitle.styling"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadSettings()
    }

    public func save() {
        let dict: [String: Any] = [
            "fontFamily": fontFamily.rawValue,
            "fontSize": fontSize,
            "isBold": isBold,
            "isItalic": isItalic,
            "textColor": textColor.toHex(),
            "backgroundColor": backgroundColor.toHex(),
            "backgroundOpacity": backgroundOpacity,
            "hasOutline": hasOutline,
            "outlineColor": outlineColor.toHex(),
            "outlineWidth": outlineWidth,
            "verticalPosition": verticalPosition.rawValue,
            "bottomMargin": bottomMargin
        ]
        userDefaults.set(dict, forKey: settingsKey)
    }

    private func loadSettings() {
        guard let dict = userDefaults.dictionary(forKey: settingsKey) else { return }

        if let fontRaw = dict["fontFamily"] as? String, let font = SubtitleFont(rawValue: fontRaw) {
            fontFamily = font
        }
        if let size = dict["fontSize"] as? Double {
            fontSize = size
        }
        if let bold = dict["isBold"] as? Bool {
            isBold = bold
        }
        if let italic = dict["isItalic"] as? Bool {
            isItalic = italic
        }
        if let hex = dict["textColor"] as? String {
            textColor = Color(hex: hex)
        }
        if let hex = dict["backgroundColor"] as? String {
            backgroundColor = Color(hex: hex)
        }
        if let opacity = dict["backgroundOpacity"] as? Double {
            backgroundOpacity = opacity
        }
        if let outline = dict["hasOutline"] as? Bool {
            hasOutline = outline
        }
        if let hex = dict["outlineColor"] as? String {
            outlineColor = Color(hex: hex)
        }
        if let width = dict["outlineWidth"] as? Double {
            outlineWidth = width
        }
        if let posRaw = dict["verticalPosition"] as? String, let pos = SubtitlePosition(rawValue: posRaw) {
            verticalPosition = pos
        }
        if let margin = dict["bottomMargin"] as? Double {
            bottomMargin = margin
        }
    }

    public func reset() {
        fontFamily = .system
        fontSize = 20
        isBold = false
        isItalic = false
        textColor = .white
        backgroundColor = .black
        backgroundOpacity = 0.7
        hasOutline = true
        outlineColor = .black
        outlineWidth = 2
        verticalPosition = .bottom
        bottomMargin = 60
        save()
    }
}

public enum SubtitleFont: String, CaseIterable {
    case system = "system"
    case arial = "Arial"
    case helvetica = "Helvetica"
    case timesNewRoman = "Times New Roman"
    case courier = "Courier"

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .arial: return "Arial"
        case .helvetica: return "Helvetica"
        case .timesNewRoman: return "Times New Roman"
        case .courier: return "Courier"
        }
    }
}

public enum SubtitlePosition: String, CaseIterable {
    case top = "top"
    case bottom = "bottom"

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

// MARK: - Color Extensions

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else { return "#FFFFFF" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
