import Foundation
import Observation
#if canImport(Speech)
import Speech
#endif
@preconcurrency import AVFoundation

@MainActor
@Observable
public final class VoiceCommandService {
    public static let shared = VoiceCommandService()
    
    public private(set) var isListening = false
    public private(set) var lastCommand: String?
    
    #if canImport(Speech)
    public private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    #endif
    
    private let audioEngine = AVAudioEngine()
    
    public weak var playerCore: PlayerCore?
    public var channelProvider: (() -> [Channel])?
    
    private init() {
        #if canImport(Speech)
        requestAuthorization()
        #endif
    }
    
    #if canImport(Speech)
    public func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }
    }
    
    public func startListening() throws {
        guard authorizationStatus == .authorized else {
            throw VoiceCommandError.notAuthorized
        }
        
        guard !isListening else { return }
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceCommandError.recognitionFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    self?.processCommand(transcript)
                    
                    if result.isFinal {
                        self?.stopListening()
                    }
                }
                
                if error != nil {
                    self?.stopListening()
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isListening = true
    }
    
    public func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
    }
    
    private func processCommand(_ text: String) {
        lastCommand = text
        let lowercased = text.lowercased()
        
        if lowercased.contains("play") {
            if let channelName = extractChannelName(from: lowercased) {
                playChannel(named: channelName)
            }
        } else if lowercased.contains("next") || lowercased.contains("skip") {
            playerCore?.playNext()
        } else if lowercased.contains("previous") || lowercased.contains("back") {
            playerCore?.playPrevious()
        } else if lowercased.contains("pause") || lowercased.contains("stop") {
            playerCore?.pause()
        } else if lowercased.contains("resume") || lowercased.contains("continue") {
            playerCore?.resume()
        } else if lowercased.contains("volume up") || lowercased.contains("louder") {
            if let currentVolume = playerCore?.volume {
                playerCore?.setVolume(min(1.0, currentVolume + 0.1))
            }
        } else if lowercased.contains("volume down") || lowercased.contains("quieter") {
            if let currentVolume = playerCore?.volume {
                playerCore?.setVolume(max(0.0, currentVolume - 0.1))
            }
        } else if lowercased.contains("mute") {
            playerCore?.toggleMute()
        }
    }
    
    private func extractChannelName(from text: String) -> String? {
        let patterns = [
            "play (.+)",
            "watch (.+)",
            "switch to (.+)",
            "change to (.+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private func playChannel(named name: String) {
        guard let channels = channelProvider?() else { return }
        
        let matchingChannel = channels.first { channel in
            channel.name.lowercased().contains(name.lowercased())
        }
        
        if let channel = matchingChannel {
            playerCore?.play(channel)
        }
    }
    #endif
}

public enum VoiceCommandError: Error {
    case notAuthorized
    case recognitionFailed
}
