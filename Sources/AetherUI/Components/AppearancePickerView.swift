import SwiftUI

/// Picker for system appearance (Light/Dark/Auto).
public struct AppearancePickerView: View {
    @AppStorage("preferredColorScheme") private var preferredScheme: String = "auto"
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tryb kolorów")
                .font(.headline)
            
            Picker("", selection: $preferredScheme) {
                Text("Automatyczny").tag("auto")
                Text("Jasny").tag("light")
                Text("Ciemny").tag("dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
