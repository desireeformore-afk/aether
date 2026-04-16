import Foundation

/// Persists the last-played channel URL to UserDefaults so it can be restored on relaunch.
public struct LastChannelStore {

    private static let urlKey = "aether.lastChannelURL"
    private static let nameKey = "aether.lastChannelName"
    private static let groupKey = "aether.lastChannelGroup"
    private static let epgIdKey = "aether.lastChannelEPGID"
    private static let logoKey = "aether.lastChannelLogoURL"

    public init() {}

    /// Saves the last-played channel to UserDefaults.
    public func save(_ channel: Channel) {
        let defaults = UserDefaults.standard
        defaults.set(channel.streamURL.absoluteString, forKey: Self.urlKey)
        defaults.set(channel.name, forKey: Self.nameKey)
        defaults.set(channel.groupTitle, forKey: Self.groupKey)
        defaults.set(channel.epgId, forKey: Self.epgIdKey)
        defaults.set(channel.logoURL?.absoluteString, forKey: Self.logoKey)
    }

    /// Restores the last-played channel from UserDefaults, or `nil` if none saved.
    public func restore() -> Channel? {
        let defaults = UserDefaults.standard
        guard
            let urlString = defaults.string(forKey: Self.urlKey),
            let url = URL(string: urlString),
            let name = defaults.string(forKey: Self.nameKey)
        else { return nil }

        let logoURL = defaults.string(forKey: Self.logoKey).flatMap { URL(string: $0) }
        return Channel(
            name: name,
            streamURL: url,
            logoURL: logoURL,
            groupTitle: defaults.string(forKey: Self.groupKey) ?? "",
            epgId: defaults.string(forKey: Self.epgIdKey)
        )
    }

    /// Clears the saved channel.
    public func clear() {
        let defaults = UserDefaults.standard
        [Self.urlKey, Self.nameKey, Self.groupKey, Self.epgIdKey, Self.logoKey]
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
