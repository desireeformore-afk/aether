import Foundation
import AetherCore

/// Engine responsible for structural deduplication and synchronization of Xstream media.
/// Removes duplicate streams (e.g. "PL DUB", "DE Disney+", "EN") and groups them under a single master object.
public struct MetaSyncEngine {
    
    /// Normalizes and groups raw Xstream categories, stripping country prefixes.
    /// Returns a deduplicated map of Clean Category Name -> [XstreamCategory IDs]
    public static func groupCategoriesByHub(_ rawCategories: [XstreamCategory]) -> [String: [String]] {
        var grouped: [String: [String]] = [:]
        
        for category in rawCategories {
            let normalized = CategoryNormalizer.normalize(
                rawID: category.id,
                rawName: category.name,
                provider: .xtream,
                contentType: .movie
            )
            guard normalized.isPrimaryVisible else { continue }
            let normalizedName = normalized.displayName
            
            if grouped[normalizedName] == nil {
                grouped[normalizedName] = []
            }
            grouped[normalizedName]?.append(category.id)
        }
        
        return grouped
    }
    
    /// Merges VOD streams with the same core title but different regional/quality tags into a single media entity.
    public static func deduplicateVODs(_ rawVODs: [XstreamVOD]) -> [XstreamVOD] {
        var mergedVODs: [String: XstreamVOD] = [:]
        
        for vod in rawVODs {
            let coreTitle = VODNormalizer.cleanVODTitle(vod.name).lowercased()
            
            if let existing = mergedVODs[coreTitle] {
                // Determine if this VOD is better (e.g. 4k > HD, PL > DE depending on preferences)
                // For now, we prefer items with higher TMDB score (which we don't have yet) or we just keep the first one
                // and maybe merge the stream IDs in a future "Alternate Streams" field.
                
                // Let's bias towards PL streams if exists
                if vod.name.uppercased().contains("PL") && !existing.name.uppercased().contains("PL") {
                    mergedVODs[coreTitle] = vod
                }
            } else {
                mergedVODs[coreTitle] = vod
            }
        }
        
        return Array(mergedVODs.values)
    }
    
    // Category cleanup lives in AetherCore.CategoryNormalizer.
}
