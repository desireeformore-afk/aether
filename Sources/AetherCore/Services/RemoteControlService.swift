import Foundation
import Observation
#if canImport(Network)
import Network
#endif

@MainActor
@Observable
public final class RemoteControlService {
    public static let shared = RemoteControlService()
    
    public private(set) var isServerRunning = false
    public private(set) var serverPort: UInt16 = 8080
    public private(set) var connectedClients: [RemoteClient] = []
    
    #if canImport(Network)
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    #endif
    
    public weak var playerCore: PlayerCore?
    
    private init() {}
    
    #if canImport(Network)
    public func startServer(port: UInt16 = 8080) throws {
        guard !isServerRunning else { return }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isServerRunning = true
                    self?.serverPort = port
                case .failed, .cancelled:
                    self?.isServerRunning = false
                default:
                    break
                }
            }
        }
        
        listener?.start(queue: .main)
    }
    
    public func stopServer() {
        #if canImport(Network)
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        #endif
        connectedClients.removeAll()
        isServerRunning = false
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        #if canImport(Network)
        connections.append(connection)
        
        let client = RemoteClient(
            id: UUID(),
            name: "Remote \(connections.count)",
            connectedAt: Date()
        )
        connectedClients.append(client)
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .cancelled = state {
                    self?.connections.removeAll { $0 === connection }
                    self?.connectedClients.removeAll { $0.id == client.id }
                }
            }
        }
        
        connection.start(queue: .main)
        receiveMessage(from: connection)
        #endif
    }
    
    private func receiveMessage(from connection: NWConnection) {
        #if canImport(Network)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    self?.handleMessage(data, from: connection)
                }
                
                if !isComplete {
                    self?.receiveMessage(from: connection)
                }
            }
        }
        #endif
    }
    
    private func handleMessage(_ data: Data, from connection: NWConnection) {
        #if canImport(Network)
        guard let message = try? JSONDecoder().decode(RemoteCommand.self, from: data) else {
            return
        }
        
        switch message.action {
        case "play":
            if let channelID = message.channelID,
               let channel = findChannel(by: channelID) {
                playerCore?.play(channel)
            }
        case "pause":
            playerCore?.pause()
        case "resume":
            playerCore?.resume()
        case "stop":
            playerCore?.stop()
        case "next":
            playerCore?.playNext()
        case "previous":
            playerCore?.playPrevious()
        case "volume":
            if let volume = message.volume {
                playerCore?.setVolume(volume)
            }
        case "mute":
            playerCore?.toggleMute()
        default:
            break
        }
        
        sendResponse(to: connection, success: true)
        #endif
    }
    
    private func sendResponse(to connection: NWConnection, success: Bool) {
        #if canImport(Network)
        let response = RemoteResponse(success: success, timestamp: Date())
        if let data = try? JSONEncoder().encode(response) {
            connection.send(content: data, completion: .idempotent)
        }
        #endif
    }
    #endif
    
    private func findChannel(by id: String) -> Channel? {
        // This would need access to PlaylistManager
        return nil
    }
}

public struct RemoteClient: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let connectedAt: Date
}

public struct RemoteCommand: Codable {
    public let action: String
    public let channelID: String?
    public let volume: Float?
}

public struct RemoteResponse: Codable {
    public let success: Bool
    public let timestamp: Date
}
