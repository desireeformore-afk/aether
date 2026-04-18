import SwiftUI
import AetherCore

struct RemoteControlView: View {
    @State private var remoteControl = RemoteControlService.shared
    @State private var serverPort: String = "8080"
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Form {
            Section("Server Status") {
                HStack {
                    Text("Status")
                    Spacer()
                    if remoteControl.isServerRunning {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                        Text("Running")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(.secondary)
                        Text("Stopped")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if remoteControl.isServerRunning {
                    HStack {
                        Text("Port")
                        Spacer()
                        Text("\(remoteControl.serverPort)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("URL")
                        Spacer()
                        Text("http://localhost:\(remoteControl.serverPort)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Controls") {
                if remoteControl.isServerRunning {
                    Button("Stop Server", role: .destructive) {
                        remoteControl.stopServer()
                    }
                } else {
                    HStack {
                        Text("Port")
                        TextField("8080", text: $serverPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    
                    Button("Start Server") {
                        startServer()
                    }
                }
            }
            
            Section("Connected Clients (\(remoteControl.connectedClients.count))") {
                if remoteControl.connectedClients.isEmpty {
                    Text("No clients connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remoteControl.connectedClients) { client in
                        HStack {
                            Image(systemName: "iphone")
                            VStack(alignment: .leading) {
                                Text(client.name)
                                Text("Connected \(client.connectedAt, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            Section("API Commands") {
                Text("POST /api/play?channelId=...")
                    .font(.system(.caption, design: .monospaced))
                Text("POST /api/pause")
                    .font(.system(.caption, design: .monospaced))
                Text("POST /api/resume")
                    .font(.system(.caption, design: .monospaced))
                Text("POST /api/next")
                    .font(.system(.caption, design: .monospaced))
                Text("POST /api/previous")
                    .font(.system(.caption, design: .monospaced))
                Text("POST /api/volume?level=0.5")
                    .font(.system(.caption, design: .monospaced))
            }
            
            Section {
                Text("Enable remote control to control Aether from other devices on your network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Remote Control")
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startServer() {
        guard let port = UInt16(serverPort) else {
            errorMessage = "Invalid port number"
            showError = true
            return
        }
        
        do {
            try remoteControl.startServer(port: port)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
