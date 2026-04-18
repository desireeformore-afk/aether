import Foundation
import GoogleCast

@MainActor
public final class ChromecastService: ObservableObject {
    public static let shared = ChromecastService()
    
    @Published public private(set) var isConnected = false
    @Published public private(set) var isCasting = false
    @Published public private(set) var deviceName: String?
    @Published public private(set) var availableDevices: [GCKDevice] = []
    
    private var sessionManager: GCKSessionManager?
    private var remoteMediaClient: GCKRemoteMediaClient?
    
    private init() {
        setupChromecast()
    }
    
    private func setupChromecast() {
        let options = GCKCastOptions(discoveryCriteria: GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID))
        GCKCastContext.setSharedInstanceWith(options)
        
        sessionManager = GCKCastContext.sharedInstance().sessionManager
        sessionManager?.add(self)
    }
    
    public func castChannel(_ channel: Channel) {
        guard let sessionManager = sessionManager,
              sessionManager.hasConnectedCastSession(),
              let remoteMediaClient = sessionManager.currentCastSession?.remoteMediaClient else {
            return
        }
        
        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(channel.name, forKey: kGCKMetadataKeyTitle)
        
        if let logoURL = channel.logoURL {
            metadata.addImage(GCKImage(url: logoURL, width: 200, height: 200))
        }
        
        let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: channel.url)
        mediaInfoBuilder.streamType = .live
        mediaInfoBuilder.contentType = "application/x-mpegURL"
        mediaInfoBuilder.metadata = metadata
        
        let mediaInfo = mediaInfoBuilder.build()
        
        remoteMediaClient.loadMedia(mediaInfo)
        isCasting = true
    }
    
    public func stopCasting() {
        guard let remoteMediaClient = sessionManager?.currentCastSession?.remoteMediaClient else {
            return
        }
        
        remoteMediaClient.stop()
        isCasting = false
    }
    
    public func disconnect() {
        sessionManager?.endSession()
    }
}

extension ChromecastService: GCKSessionManagerListener {
    public func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        isConnected = true
        deviceName = session.device.friendlyName
        remoteMediaClient = session.remoteMediaClient
    }
    
    public func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        isConnected = false
        deviceName = nil
        isCasting = false
        remoteMediaClient = nil
    }
}
