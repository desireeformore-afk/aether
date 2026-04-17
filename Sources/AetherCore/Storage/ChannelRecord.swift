import Foundation

/// Legacy channel record — replaced by ChannelCache (JSON file storage).
/// Kept for source compatibility only. Not registered in any ModelContainer.
@available(*, deprecated, renamed: "Channel", message: "Use Channel + ChannelCache instead of SwiftData for channel storage.")
public struct ChannelRecord {
    public var id: UUID
    public var name: String
    public var streamURLString: String
    public var logoURLString: String?
    public var groupTitle: String
    public var epgId: String?
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        streamURLString: String,
        logoURLString: String? = nil,
        groupTitle: String = "Uncategorized",
        epgId: String? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.streamURLString = streamURLString
        self.logoURLString = logoURLString
        self.groupTitle = groupTitle
        self.epgId = epgId
        self.sortIndex = sortIndex
    }

    public func toChannel() -> Channel? {
        guard let url = URL(string: streamURLString) else { return nil }
        return Channel(
            id: id,
            name: name,
            streamURL: url,
            logoURL: logoURLString.flatMap { URL(string: $0) },
            groupTitle: groupTitle,
            epgId: epgId
        )
    }
}
