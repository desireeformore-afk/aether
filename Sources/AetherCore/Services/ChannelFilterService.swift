import Foundation
import AetherCore

/// Pure, stateless service for filtering and grouping channel lists.
public struct ChannelFilterService: Sendable {

    public init() {}

    /// Returns sorted unique group titles from the given channels.
    /// Excludes empty strings.
    public func groups(from channels: [Channel]) -> [String] {
        let all = channels.map(\.groupTitle).filter { !$0.isEmpty }
        return Array(Set(all)).sorted()
    }

    /// Filters channels by optional group and/or search query.
    /// - Parameters:
    ///   - group: If non-nil, only channels with this groupTitle are included.
    ///   - searchQuery: Case-insensitive match against name or groupTitle.
    public func filter(channels: [Channel], group: String?, searchQuery: String) -> [Channel] {
        channels.filter { channel in
            let matchesGroup = group == nil || channel.groupTitle == group
            let matchesSearch: Bool
            if searchQuery.isEmpty {
                matchesSearch = true
            } else {
                let q = searchQuery.lowercased()
                matchesSearch = channel.name.lowercased().contains(q)
                    || channel.groupTitle.lowercased().contains(q)
            }
            return matchesGroup && matchesSearch
        }
    }
}
