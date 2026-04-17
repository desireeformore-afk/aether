import SwiftUI
import AetherCore

/// First-launch onboarding — shown until user adds their first playlist.
/// Platform-agnostic. Parent controls `isPresented`.
public struct OnboardingView: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    @State private var step = 0

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomePage.tag(0)
                addPlaylistPage.tag(1)
                readyPage.tag(2)
            }
            #if os(macOS) || os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.borderless)
                }
                Spacer()
                if step < 2 {
                    Button("Next") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 480, height: 380)
        #endif
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.aetherAccent)
            Text("Welcome to Aether")
                .font(.largeTitle).bold()
            Text("Your personal IPTV player — channels, VOD, and series in one place.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var addPlaylistPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 64))
                .foregroundStyle(Color.aetherAccent)
            Text("Add Your Playlist")
                .font(.largeTitle).bold()
            Text("Paste an M3U URL or enter your Xtream Codes credentials.\nYou can add more playlists anytime from the sidebar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var readyPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.largeTitle).bold()
            Text("Tap the + button in the sidebar to add your first playlist.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}
