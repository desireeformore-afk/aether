import Foundation

/// Age rating for content classification.
///
/// Represents standard content ratings used for parental control filtering.
public enum AgeRating: String, Codable, Sendable, CaseIterable, Comparable {
    case g = "G"
    case pg = "PG"
    case pg13 = "PG-13"
    case r = "R"
    case nc17 = "NC-17"
    case unrated = "Unrated"

    /// Numeric value for comparison (lower = less restrictive).
    public var numericValue: Int {
        switch self {
        case .g: return 0
        case .pg: return 1
        case .pg13: return 2
        case .r: return 3
        case .nc17: return 4
        case .unrated: return 5
        }
    }

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .g: return "G - General Audiences"
        case .pg: return "PG - Parental Guidance"
        case .pg13: return "PG-13 - Parents Strongly Cautioned"
        case .r: return "R - Restricted"
        case .nc17: return "NC-17 - Adults Only"
        case .unrated: return "Unrated"
        }
    }

    public static func < (lhs: AgeRating, rhs: AgeRating) -> Bool {
        lhs.numericValue < rhs.numericValue
    }
}
