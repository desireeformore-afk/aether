import SwiftUI
import AetherCore

struct WatchPartyView: View {
    @StateObject private var watchParty = WatchPartyService.shared
    @State private var partyCodeInput = ""
    @State private var messageInput = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            if watchParty.isHosting || watchParty.isJoined {
                activePartyView
            } else {
                setupView
            }
        }
        .navigationTitle("Watch Party")
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple)
            
            Text("Watch Together")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Watch channels with friends in sync")
                .foregroundStyle(.secondary)
            
            Divider()
                .padding(.vertical)
            
            VStack(spacing: 12) {
                Button {
                    let code = watchParty.createParty()
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    #endif
                } label: {
                    Label("Create Party", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                HStack {
                    TextField("Enter party code", text: $partyCodeInput)
                        .textFieldStyle(.roundedBorder)
                        .textCase(.uppercase)
                    
                    Button("Join") {
                        joinParty()
                    }
                    .buttonStyle(.bordered)
                    .disabled(partyCodeInput.isEmpty)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: 400)
    }
    
    private var activePartyView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Participants")
                        .font(.headline)
                    Spacer()
                    Text("\(watchParty.participants.count)")
                        .foregroundStyle(.secondary)
                }
                
                if let code = watchParty.partyCode {
                    HStack {
                        Text(code)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                        
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(watchParty.participants) { participant in
                            HStack {
                                Image(systemName: participant.isHost ? "crown.fill" : "person.fill")
                                    .foregroundStyle(participant.isHost ? .yellow : .secondary)
                                
                                VStack(alignment: .leading) {
                                    Text(participant.name)
                                        .fontWeight(.medium)
                                    Text("Joined \(participant.joinedAt, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button("Leave Party", role: .destructive) {
                    watchParty.leaveParty()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 250)
            
            Divider()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(watchParty.chatMessages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(message.senderName)
                                        .fontWeight(.semibold)
                                    Text(message.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(message.text)
                            }
                            .padding(8)
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                HStack {
                    TextField("Type a message...", text: $messageInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Send") {
                        sendMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(messageInput.isEmpty)
                }
                .padding()
            }
        }
    }
    
    private func joinParty() {
        Task {
            do {
                try await watchParty.joinParty(code: partyCodeInput)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func sendMessage() {
        watchParty.sendMessage(messageInput)
        messageInput = ""
    }
}
