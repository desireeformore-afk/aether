     1|import SwiftUI
     2|import AetherCore
     3|
     4|/// Recording controls button with menu for record, timeshift, and recordings manager.
     5|struct RecordingControlsButton: View {
     6|    @Bindable var player: PlayerCore
     7|    @ObservedObject var recordingService: RecordingService
     8|    @ObservedObject var timeshiftService: TimeshiftService
     9|    @Binding var showRecordingManager: Bool
    10|
    11|    @State private var activeRecordingId: UUID?
    12|
    13|    var body: some View {
    14|        Menu {
    15|            // Record button
    16|            if let channel = player.currentChannel {
    17|                if let recordingId = activeRecordingId {
    18|                    Button(action: {
    19|                        Task {
    20|                            try? await recordingService.stopRecording(recordingId)
    21|                            activeRecordingId = nil
    22|                        }
    23|                    }) {
    24|                        Label("Stop Recording", systemImage: "stop.circle.fill")
    25|                    }
    26|                } else {
    27|                    Button(action: {
    28|                        do {
    29|                            let id = try recordingService.startRecording(channel: channel)
    30|                            activeRecordingId = id
    31|                        } catch {
    32|                            // Handle error
    33|                        }
    34|                    }) {
    35|                        Label("Start Recording", systemImage: "record.circle")
    36|                    }
    37|                }
    38|            }
    39|
    40|            Divider()
    41|
    42|            // Timeshift controls
    43|            if timeshiftService.isBuffering {
    44|                Button(action: {
    45|                    timeshiftService.stopBuffering()
    46|                }) {
    47|                    Label("Stop Timeshift", systemImage: "stop.circle")
    48|                }
    49|
    50|                if timeshiftService.isPaused {
    51|                    Button(action: {
    52|                        timeshiftService.resume()
    53|                    }) {
    54|                        Label("Resume Live", systemImage: "play.circle")
    55|                    }
    56|                } else {
    57|                    Button(action: {
    58|                        timeshiftService.pause()
    59|                    }) {
    60|                        Label("Pause Live TV", systemImage: "pause.circle")
    61|                    }
    62|                }
    63|
    64|                Button(action: {
    65|                    try? timeshiftService.jumpBack(seconds: 10)
    66|                }) {
    67|                    Label("Jump Back 10s", systemImage: "gobackward.10")
    68|                }
    69|
    70|                Button(action: {
    71|                    try? timeshiftService.jumpForward(seconds: 10)
    72|                }) {
    73|                    Label("Jump Forward 10s", systemImage: "goforward.10")
    74|                }
    75|
    76|                Section {
    77|                    Text("Buffer: \(timeshiftService.bufferDurationFormatted)")
    78|                    Text("Size: \(timeshiftService.bufferSizeFormatted)")
    79|                }
    80|            } else if let channel = player.currentChannel {
    81|                Button(action: {
    82|                    try? timeshiftService.startBuffering(for: channel.id)
    83|                }) {
    84|                    Label("Enable Timeshift", systemImage: "clock.arrow.circlepath")
    85|                }
    86|            }
    87|
    88|            Divider()
    89|
    90|            // Recordings manager
    91|            Button(action: {
    92|                showRecordingManager = true
    93|            }) {
    94|                Label("Manage Recordings", systemImage: "film.stack")
    95|            }
    96|        } label: {
    97|            Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
    98|                .font(.title3)
    99|                .foregroundStyle(isRecording ? .red : Color.aetherText)
   100|        }
   101|        .menuStyle(.borderlessButton)
   102|        .help("Recording & Timeshift")
   103|    }
   104|
   105|    private var isRecording: Bool {
   106|        activeRecordingId != nil || !recordingService.activeRecordings.isEmpty
   107|    }
   108|}
   109|