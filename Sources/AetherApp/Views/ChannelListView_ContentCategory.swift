import Foundation

// MARK: - ContentCategory

enum ContentCategory: String, CaseIterable {
    case all, tv, movies, series
    
    var label: String {
        switch self {
        case .all:    return "Wszystkie"
        case .tv:     return "TV"
        case .movies: return "Filmy"
        case .series: return "Seriale"
        }
    }
}
