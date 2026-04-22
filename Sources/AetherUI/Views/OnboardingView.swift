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
                addServerPage.tag(1)
                readyPage.tag(2)
            }
            #if os(iOS) || os(tvOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            HStack {
                // Skip — always visible, dismisses onboarding immediately
                Button("Pomiń") { isPresented = false }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                Spacer()

                if step > 0 {
                    Button("Wstecz") { step -= 1 }
                        .buttonStyle(.borderless)
                }

                if step < 2 {
                    Button("Dalej") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Zacznij oglądać") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 480, height: 400)
        #endif
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.aetherAccent)
            Text("Witaj w Aether")
                .font(.largeTitle).bold()
            Text("Premium IPTV dla macOS — kanały, filmy i seriale w jednym miejscu.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var addServerPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(Color.aetherAccent)
            Text("Dodaj serwer")
                .font(.largeTitle).bold()
            Text("Wklej link M3U lub podaj dane dostępowe Xtream Codes.\nSerwer możesz też dodać później w Ustawienia → Konto.")
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
            Text("Gotowe!")
                .font(.largeTitle).bold()
            Text("Kliknij przycisk + na pasku bocznym, aby dodać swoją pierwszą playlistę.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}
