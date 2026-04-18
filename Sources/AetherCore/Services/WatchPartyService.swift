import Foundation

@MainActor
public final class WatchPartyService: ObservableObject {
    public static let shared = WatchPartyService()
    
    @Published public private(set) var isHosting = false
    @Published public private(set) var isJoined = false
    @Published public private(set) var partyCode: String?
    @Published public private(set) var participants: [Participant] = []
    @Published public private(set) var chatMessages: [ChatMessage] = []
    
    private var syncTimer: Timer?
    
    public weak var playerCore: PlayerCore?
    
    private init() {}
    
    public func createParty() -> String {
        let code = generatePartyCode()
        partyCode = code
        isHosting = true
        
        let host = Participant(
            id: UUID(),
            name: "You",
            isHost: true,
            joinedAt: Date()
        )
        participants = [host]
        
        startSyncTimer()
        return code
    }
    
    public func joinParty(code: String) async throws {
        // In real implementation, this would connect to a server
        partyCode = code
        isJoined = true
        
        let participant = Participant(
            id: UUID(),
            name: "Guest",
            isHost: false,
            joinedAt: Date()
        )
        participants.append(participant)
        
        startSyncTimer()
    }
    
    public func leaveParty() {
        stopSyncTimer()
        partyCode = nil
        isHosting = false
        isJoined = false
        participants.removeAll()
        chatMessages.removeAll()
    }
    
    public func sendMessage(_ text: String) {
        let message = ChatMessage(
            id: UUID(),
            senderName: "You",
            text: text,
            timestamp: Date()
        )
        chatMessages.append(message)
        
        // In real implementation, broadcast to all participants
    }
    
    public func syncPlayback(position: TimeInterval, isPlaying: Bool) {
        guard isHosting else { return }
        
        // In real implementation, broadcast playback state to all participants
    }
    
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncPlaybackState()
            }
        }
    }
    
    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func syncPlaybackState() {
        guard let playerCore = playerCore else { return }

        if isHosting {
            // Broadcast current playback state
            let currentTime = playerCore.currentTime
            let isPlaying = playerCore.state == .playing
            syncPlayback(position: currentTime, isPlaying: isPlaying)
        } else if isJoined {
            // Receive and apply playback state from host
        }
    }
    
    private func generatePartyCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}

public struct Participant: Identifiable {
    public let id: UUID
    public let name: String
    public let isHost: Bool
    public let joinedAt: Date
}

public struct ChatMessage: Identifiable {
    public let id: UUID
    public let senderName: String
    public let text: String
    public let timestamp: Date
}
