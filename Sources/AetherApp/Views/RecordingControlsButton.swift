import SwiftUI
import AetherCore

/// Recording controls button with menu for record, timeshift, and recordings manager.
struct RecordingControlsButton: View {
    @Bindable var player: PlayerCore
    @State var recordingService: RecordingService
    @Bindable var timeshiftService: TimeshiftService
    @Binding var showRecordingManager: Bool

    @State private var activeRecordingId: UUID?

    var body: some View {
        Menu {
            // Record button
            if let channel = player.currentChannel {
                if let recordingId = activeRecordingId {
                    Button(action: {
                        Task {
                            try? await recordingService.stopRecording(recordingId)
                            activeRecordingId = nil
                        }
                    }) {
                        Label("Stop Recording", systemImage: "stop.circle.fill")
                    }
                } else {
                    Button(action: {
                        do {
                            let id = try recordingService.startRecording(channel: channel)
                            activeRecordingId = id
                        } catch {
                            // Handle error
                        }
                    }) {
                        Label("Start Recording", systemImage: "record.circle")
                    }
                }
            }

            Divider()

            // Timeshift controls
            if timeshiftService.isBuffering {
                Button(action: {
                    timeshiftService.stopBuffering()
                }) {
                    Label("Stop Timeshift", systemImage: "stop.circle")
                }

                if timeshiftService.isPaused {
                    Button(action: {
                        timeshiftService.resume()
                    }) {
                        Label("Resume Live", systemImage: "play.circle")
                    }
                } else {
                    Button(action: {
                        timeshiftService.pause()
                    }) {
                        Label("Pause Live TV", systemImage: "pause.circle")
                    }
                }

                Button(action: {
                    try? timeshiftService.jumpBack(seconds: 10)
                }) {
                    Label("Jump Back 10s", systemImage: "gobackward.10")
                }

                Button(action: {
                    try? timeshiftService.jumpForward(seconds: 10)
                }) {
                    Label("Jump Forward 10s", systemImage: "goforward.10")
                }

                Section("Buffer Info") {
                    Text("Buffer: \(timeshiftService.bufferDurationFormatted)")
                    Text("Size: \(timeshiftService.bufferSizeFormatted)")
                }
            } else if let channel = player.currentChannel {
                Button(action: {
                    try? timeshiftService.startBuffering(for: channel.id)
                }) {
                    Label("Enable Timeshift", systemImage: "clock.arrow.circlepath")
                }
            }

            Divider()

            // Recordings manager
            Button(action: {
                showRecordingManager = true
            }) {
                Label("Manage Recordings", systemImage: "film.stack")
            }
        } label: {
            Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                .font(.title3)
                .foregroundStyle(isRecording ? .red : Color.aetherText)
        }
        .menuStyle(.borderlessButton)
        .help("Recording & Timeshift")
    }

    private var isRecording: Bool {
        activeRecordingId != nil || !recordingService.activeRecordings.isEmpty
    }
}
