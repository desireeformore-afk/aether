import SwiftUI
import SwiftData
import AetherCore

@main
struct AetherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [])
    }
}

struct ContentView: View {
    var body: some View {
        Text("Aether")
            .font(.aetherTitle)
            .foregroundStyle(.aetherPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.aetherBackground)
    }
}
