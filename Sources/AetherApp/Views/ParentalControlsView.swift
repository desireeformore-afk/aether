import SwiftUI

/// PIN entry view for parental controls.
struct PINEntryView: View {
    let title: String
    let message: String?
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var pin: String = ""
    @State private var showError: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 8)

            if showError {
                Text("Incorrect PIN")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Number pad
            VStack(spacing: 12) {
                ForEach(0..<3) { row in
                    HStack(spacing: 12) {
                        ForEach(1..<4) { col in
                            let number = row * 3 + col
                            NumberButton(number: "\(number)") {
                                appendDigit("\(number)")
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(width: 80, height: 80)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    NumberButton(number: "0") {
                        appendDigit("0")
                    }

                    Button(action: deleteDigit) {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .frame(width: 80, height: 80)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }

    private func appendDigit(_ digit: String) {
        guard pin.count < 4 else { return }
        pin.append(digit)
        showError = false

        if pin.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onComplete(pin)
                pin = ""
            }
        }
    }

    private func deleteDigit() {
        if !pin.isEmpty {
            pin.removeLast()
            showError = false
        }
    }
}

struct NumberButton: View {
    let number: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.title)
                .fontWeight(.medium)
                .frame(width: 80, height: 80)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Parental controls settings view.
public struct ParentalControlsView: View {
    @ObservedObject var service: ParentalControlService
    @Environment(\.dismiss) private var dismiss

    @State private var showPINSetup = false
    @State private var showPINChange = false
    @State private var showPINEntry = false
    @State private var showError: String?
    @State private var newMaxRating: AgeRating
    @State private var showAddTimeRestriction = false

    public init(service: ParentalControlService) {
        self.service = service
        _newMaxRating = State(initialValue: service.settings.maxAgeRating)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Parental Controls")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Enable/Disable
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Parental Controls", isOn: Binding(
                                get: { service.settings.isEnabled },
                                set: { newValue in
                                    if newValue && service.settings.pinHash == nil {
                                        showPINSetup = true
                                    } else {
                                        var settings = service.settings
                                        settings.isEnabled = newValue
                                        try? service.updateSettings(settings)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)

                            if service.settings.isEnabled {
                                Text("Parental controls are active. Content will be filtered based on your settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if service.settings.isEnabled {
                        // PIN Management
                        GroupBox("PIN Settings") {
                            VStack(alignment: .leading, spacing: 12) {
                                if service.settings.pinHash != nil {
                                    Button("Change PIN") {
                                        showPINChange = true
                                    }

                                    Button("Reset PIN", role: .destructive) {
                                        try? service.resetPIN()
                                    }
                                } else {
                                    Button("Set Up PIN") {
                                        showPINSetup = true
                                    }
                                }

                                Toggle("Require PIN for Settings", isOn: Binding(
                                    get: { service.settings.requirePINForSettings },
                                    set: { newValue in
                                        var settings = service.settings
                                        settings.requirePINForSettings = newValue
                                        try? service.updateSettings(settings)
                                    }
                                ))
                            }
                        }

                        // Age Rating
                        GroupBox("Age Rating Limit") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Maximum Rating", selection: $newMaxRating) {
                                    ForEach(AgeRating.allCases, id: \.self) { rating in
                                        Text(rating.displayName).tag(rating)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: newMaxRating) { _, newValue in
                                    var settings = service.settings
                                    settings.maxAgeRating = newValue
                                    try? service.updateSettings(settings)
                                }

                                Text("Content rated above \(newMaxRating.rawValue) will be blocked.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Time Restrictions
                        GroupBox("Time Restrictions") {
                            VStack(alignment: .leading, spacing: 12) {
                                if service.settings.timeRestrictions.isEmpty {
                                    Text("No time restrictions set")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(service.settings.timeRestrictions) { restriction in
                                        TimeRestrictionRow(restriction: restriction) {
                                            try? service.removeTimeRestriction(restriction.id)
                                        }
                                    }
                                }

                                Button("Add Time Restriction") {
                                    showAddTimeRestriction = true
                                }
                            }
                        }

                        // Session Status
                        if service.isUnlocked {
                            GroupBox {
                                HStack {
                                    Image(systemName: "lock.open.fill")
                                        .foregroundStyle(.green)
                                    Text("Session Unlocked")
                                        .font(.subheadline)
                                    Spacer()
                                    Button("Lock Now") {
                                        service.lockSession()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
        .sheet(isPresented: $showPINSetup) {
            PINSetupSheet(service: service)
        }
        .sheet(isPresented: $showPINChange) {
            PINChangeSheet(service: service)
        }
        .sheet(isPresented: $showAddTimeRestriction) {
            AddTimeRestrictionSheet(service: service)
        }
        .alert("Error", isPresented: Binding(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
    }
}

struct TimeRestrictionRow: View {
    let restriction: TimeRestriction
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(restriction.startHour):00 - \(restriction.endHour):00")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Max: \(restriction.maxAgeRating.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PINSetupSheet: View {
    @ObservedObject var service: ParentalControlService
    @Environment(\.dismiss) private var dismiss
    @State private var showPINEntry = false
    @State private var firstPIN: String?
    @State private var showError: String?

    var body: some View {
        VStack {
            if firstPIN == nil {
                PINEntryView(
                    title: "Set Up PIN",
                    message: "Enter a 4-digit PIN",
                    onComplete: { pin in
                        firstPIN = pin
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            } else {
                PINEntryView(
                    title: "Confirm PIN",
                    message: "Enter your PIN again",
                    onComplete: { pin in
                        if pin == firstPIN {
                            do {
                                try service.setupPIN(pin)
                                dismiss()
                            } catch {
                                showError = error.localizedDescription
                            }
                        } else {
                            showError = "PINs do not match"
                            firstPIN = nil
                        }
                    },
                    onCancel: {
                        firstPIN = nil
                    }
                )
            }
        }
        .alert("Error", isPresented: Binding(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
    }
}

struct PINChangeSheet: View {
    @ObservedObject var service: ParentalControlService
    @Environment(\.dismiss) private var dismiss
    @State private var currentPIN: String?
    @State private var newPIN: String?
    @State private var showError: String?

    var body: some View {
        VStack {
            if currentPIN == nil {
                PINEntryView(
                    title: "Enter Current PIN",
                    message: nil,
                    onComplete: { pin in
                        if service.validatePIN(pin) {
                            currentPIN = pin
                        } else {
                            showError = "Incorrect PIN"
                        }
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            } else if newPIN == nil {
                PINEntryView(
                    title: "Enter New PIN",
                    message: nil,
                    onComplete: { pin in
                        newPIN = pin
                    },
                    onCancel: {
                        currentPIN = nil
                    }
                )
            } else {
                PINEntryView(
                    title: "Confirm New PIN",
                    message: nil,
                    onComplete: { pin in
                        if pin == newPIN, let current = currentPIN {
                            do {
                                try service.changePIN(current: current, new: pin)
                                dismiss()
                            } catch {
                                showError = error.localizedDescription
                            }
                        } else {
                            showError = "PINs do not match"
                            newPIN = nil
                        }
                    },
                    onCancel: {
                        newPIN = nil
                    }
                )
            }
        }
        .alert("Error", isPresented: Binding(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
    }
}

struct AddTimeRestrictionSheet: View {
    @ObservedObject var service: ParentalControlService
    @Environment(\.dismiss) private var dismiss

    @State private var startHour: Int = 22
    @State private var endHour: Int = 6
    @State private var maxRating: AgeRating = .pg
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Time Restriction")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Picker("Start Hour", selection: $startHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }

                Picker("End Hour", selection: $endHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }

                Picker("Maximum Rating", selection: $maxRating) {
                    ForEach(AgeRating.allCases, id: \.self) { rating in
                        Text(rating.rawValue).tag(rating)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let restriction = TimeRestriction(
                        startHour: startHour,
                        endHour: endHour,
                        maxAgeRating: maxRating,
                        daysOfWeek: selectedDays
                    )
                    try? service.addTimeRestriction(restriction)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
        .padding()
    }
}
