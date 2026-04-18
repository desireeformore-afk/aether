import SwiftUI
import AetherCore

/// PIN lock overlay for restricted content.
public struct PINLockView: View {
    let reason: String
    let onUnlock: () -> Void
    let onCancel: () -> Void

    @Bindable var service: ParentalControlService
    @State private var showPINEntry = false
    @State private var attemptedPIN: String = ""
    @State private var showError = false

    public init(
        reason: String,
        service: ParentalControlService,
        onUnlock: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.reason = reason
        self.service = service
        self.onUnlock = onUnlock
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)

                    Text("Content Restricted")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    Button("Enter PIN to Unlock") {
                        showPINEntry = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Go Back") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(48)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 30)
        }
        .sheet(isPresented: $showPINEntry) {
            PINEntryView(
                title: "Enter PIN",
                message: "Enter your parental control PIN to unlock this content",
                onComplete: { pin in
                    if service.validatePIN(pin) {
                        showPINEntry = false
                        onUnlock()
                    } else {
                        showError = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            showError = false
                        }
                    }
                },
                onCancel: {
                    showPINEntry = false
                }
            )
        }
    }
}
