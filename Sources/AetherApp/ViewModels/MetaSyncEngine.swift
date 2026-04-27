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
            var normalizedName = cleanCategoryName(category.name)
            
            // Fallback if regex stripped the entire name (e.g., category was strictly "PL 4K")
            if normalizedName.isEmpty {
                normalizedName = category.name.trimmingCharacters(in: .whitespaces)
            }
            
            // Skip pure garbage
            if isGarbage(normalizedName) { continue }
            
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
    
    // MARK: - internal cleaning algorithms
    
    private static func cleanCategoryName(_ rawName: String) -> String {
        var name = rawName
        
        // Remove known exact prefixes like "PL |", "DE - ", "UK:", "VOD"
        let pattern = "^(PL|DE|UK|US|ES|FR|IT|TR|NL|RU|RO|VOD|VIP|4K|FHD|HD)[\\s\\|\\-\\:]+"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: name.utf16.count)
            name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        }
        
        // Catch suffixes "[PL]" or "(DE)" or " PL"
        let suffixPattern = "[\\s\\-\\|]*[\\(\\[]?(PL|DE|UK|US|ES|FR|IT|TR|NL|RU|RO|VOD|VIP)[\\)\\]]?$"
        if let regex = try? NSRegularExpression(pattern: suffixPattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: name.utf16.count)
            name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        }
        
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func isGarbage(_ name: String) -> Bool {
        let n = name.lowercased()
        let junk = ["xxx", "adult", "test", "for adults", "24/7", "vip", "zapasowe", "backup", "inne"]
        
        // Check Arabic/RTL script
        if name.unicodeScalars.contains(where: { $0.value > 0x0600 && $0.value < 0x06FF }) { return true }
        
        return junk.contains { n.contains($0) }
    }
}
