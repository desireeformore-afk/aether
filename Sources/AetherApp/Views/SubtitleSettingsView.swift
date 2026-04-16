import SwiftUI
import AetherCore

struct SubtitleSettingsView: View {
    @AppStorage("subtitle_fontSize")   private var fontSize: Double = 22
    @AppStorage("subtitle_offsetY")    private var offsetY: Double = 32
    @AppStorage("subtitle_textColor")  private var textColorHex: String = "#FFFFFF"
    @AppStorage("subtitle_bgOpacity")  private var bgOpacity: Double = 0.55
    @AppStorage("opensubtitles_api_key") private var apiKey: String = ""

    var body: some View {
        Form {
            Section("OpenSubtitles") {
                TextField("API Key (opensubtitles.com → Consumers)", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Link("Get free API key →", destination: URL(string: "https://www.opensubtitles.com/consumers")!)
                    .font(.caption)
            }

            Section("Appearance") {
                HStack {
                    Text("Font size")
                    Spacer()
                    Slider(value: $fontSize, in: 14...48, step: 1)
                        .frame(width: 160)
                    Text("\(Int(fontSize)) pt")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("Bottom offset")
                    Spacer()
                    Slider(value: $offsetY, in: 8...120, step: 4)
                        .frame(width: 160)
                    Text("\(Int(offsetY)) pt")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("Background opacity")
                    Spacer()
                    Slider(value: $bgOpacity, in: 0...1, step: 0.05)
                        .frame(width: 160)
                    Text("\(Int(bgOpacity * 100))%")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                // Color picker — simple presets + custom
                HStack {
                    Text("Text color")
                    Spacer()
                    ForEach(["#FFFFFF", "#FFFF00", "#00FF00", "#FF6B6B"], id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? Color.white)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(
                                textColorHex == hex ? Color.aetherAccent : Color.clear, lineWidth: 2))
                            .onTapGesture { textColorHex = hex }
                    }
                }
            }

            Section("Preview") {
                ZStack {
                    Color.black
                    Text("Przykładowy napis")
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(Color(hex: textColorHex) ?? Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(bgOpacity),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .formStyle(.grouped)
    }
}
// Color(hex:) is defined in AetherCore/Design/Colors.swift (public extension Color)
