import SwiftUI
import AetherCore

/// Segmented picker for light / dark / system appearance override.
/// Persists the choice to AppStorage("appearanceMode").
public struct AppearancePickerView: View {
    @AppStorage("appearanceMode") private var storedMode: String = AppearanceMode.system.rawValue

    private var currentMode: AppearanceMode {
        AppearanceMode(rawValue: storedMode) ?? .system
    }

    public init() {}

    public var body: some View {
        #if os(tvOS)
        // tvOS: simple menu picker
        Menu {
            ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                Button(mode.label) { storedMode = mode.rawValue }
            }
        } label: {
            Label(currentMode.label, systemImage: currentMode.icon)
        }
        #else
        Picker("Appearance", selection: Binding(
            get: { currentMode },
            set: { storedMode = $0.rawValue }
        )) {
            ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                Label(mode.label, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
        #endif
    }
}
