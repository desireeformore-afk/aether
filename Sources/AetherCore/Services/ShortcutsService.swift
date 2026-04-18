import Foundation
#if canImport(Intents)
import Intents
#endif

@MainActor
@Observable
public final class ShortcutsService {
    public static let shared = ShortcutsService()
    
    public weak var playerCore: PlayerCore?
    public var channelProvider: (() -> [Channel])?
    
    private init() {
        #if canImport(Intents)
        donateShortcuts()
        #endif
    }
    
    #if canImport(Intents)
    private func donateShortcuts() {
        // Donate "Play Favorite Channel" shortcut
        let playFavoriteIntent = PlayChannelIntent()
        playFavoriteIntent.suggestedInvocationPhrase = "Play my favorite channel"
        
        let interaction = INInteraction(intent: playFavoriteIntent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate shortcut: \(error)")
            }
        }
    }
    #endif
    
    public func handlePlayChannel(channelName: String) {
        guard let channels = channelProvider?() else { return }
        
        let matchingChannel = channels.first { channel in
            channel.name.lowercased() == channelName.lowercased()
        }
        
        if let channel = matchingChannel {
            playerCore?.play(channel)
        }
    }
    
    public func handleNextChannel() {
        playerCore?.playNext()
    }

    public func handlePreviousChannel() {
        playerCore?.playPrevious()
    }
    
    public func handleToggleParentalControls() {
        // This would toggle parental controls
    }
    
    public func handleStartRecording() {
        // This would start recording current channel
    }
}

#if canImport(Intents)
// Intent definitions would go in separate Intents.intentdefinition file
public class PlayChannelIntent: INIntent {
    @NSManaged public var channelName: String?
}

public class NextChannelIntent: INIntent {}

public class PreviousChannelIntent: INIntent {}

public class ToggleParentalControlsIntent: INIntent {}

public class StartRecordingIntent: INIntent {}
#endif
