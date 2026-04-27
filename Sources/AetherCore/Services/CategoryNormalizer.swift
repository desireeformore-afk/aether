import Foundation

/// Central category cleanup and taxonomy rules for M3U and Xtream providers.
public enum CategoryNormalizer {

    public static func normalize(
        rawID: String? = nil,
        rawName: String?,
        provider: ContentCategoryProvider = .unknown,
        contentType: ContentType
    ) -> NormalizedContentCategory {
        let raw = RawProviderCategory(
            provider: provider,
            contentType: contentType,
            rawID: normalizedOptional(rawID),
            rawName: normalizedOptional(rawName)
        )

        let sourceName = raw.rawName ?? raw.rawID ?? ""
        let collapsedSource = collapseWhitespace(sourceName)
        guard !collapsedSource.isEmpty else {
            return category(
                raw: raw,
                displayName: "Uncategorized",
                role: .hidden,
                priority: 1_000,
                isPrimaryVisible: false,
                reasons: [.empty]
            )
        }

        if raw.rawName == nil, raw.rawID != nil {
            return category(
                raw: raw,
                displayName: collapsedSource,
                role: .providerFallback,
                priority: 900,
                isPrimaryVisible: true,
                reasons: []
            )
        }

        let cleaned = cleanProviderCategoryName(collapsedSource)
        let displayCandidate = cleaned.isEmpty ? collapsedSource : cleaned
        var reasons = noiseReasons(in: collapsedSource)

        if isAdultCategory(collapsedSource) {
            return category(
                raw: raw,
                displayName: "Adult",
                role: .adult,
                priority: 1_000,
                isPrimaryVisible: false,
                reasons: appendUnique(.adult, to: reasons)
            )
        }

        if containsArabicScript(collapsedSource) {
            return category(
                raw: raw,
                displayName: displayCandidate,
                role: .providerNoise,
                priority: 980,
                isPrimaryVisible: false,
                reasons: appendUnique(.arabicScript, to: reasons)
            )
        }

        if isQualityOnly(collapsedSource) {
            return category(
                raw: raw,
                displayName: canonicalQualityName(collapsedSource),
                role: .quality,
                priority: 940,
                isPrimaryVisible: false,
                reasons: appendUnique(.qualityOnly, to: reasons)
            )
        }

        if isLanguageOnly(collapsedSource) {
            return category(
                raw: raw,
                displayName: collapsedSource.uppercased(),
                role: .language,
                priority: 920,
                isPrimaryVisible: false,
                reasons: appendUnique(.languageOnly, to: reasons)
            )
        }

        if isQualifierOnly(collapsedSource) {
            return category(
                raw: raw,
                displayName: displayCandidate.isEmpty ? "Other" : displayCandidate,
                role: .providerNoise,
                priority: 960,
                isPrimaryVisible: false,
                reasons: qualifierReasons(for: collapsedSource, existing: reasons)
            )
        }

        if isNumericOnly(collapsedSource) {
            return category(
                raw: raw,
                displayName: collapsedSource,
                role: .providerFallback,
                priority: 900,
                isPrimaryVisible: false,
                reasons: appendUnique(.numericOnly, to: reasons)
            )
        }

        if isProviderNoiseOnly(collapsedSource) || displayCandidate.isEmpty {
            return category(
                raw: raw,
                displayName: displayCandidate.isEmpty ? "Other" : displayCandidate,
                role: .providerNoise,
                priority: 960,
                isPrimaryVisible: false,
                reasons: appendUnique(.providerNoise, to: reasons)
            )
        }

        let displayName = canonicalDisplayName(for: displayCandidate, contentType: contentType)
        let role = roleForDisplayName(displayName, contentType: contentType)
        let priority = priorityForRole(role, reasons: reasons)

        return category(
            raw: raw,
            displayName: displayName,
            role: role,
            priority: priority,
            isPrimaryVisible: true,
            reasons: reasons
        )
    }

    public static func cleanProviderCategoryName(_ rawName: String) -> String {
        var name = collapseWhitespace(rawName)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[\[\]\(\)\{\}]"#, with: " ", options: .regularExpression)
        name = collapseWhitespace(name)

        for _ in 0..<4 {
            let previous = name
            name = stripEdgeToken(from: name, pattern: prefixTokenPattern)
            name = stripEdgeToken(from: name, pattern: suffixTokenPattern)
            name = collapseWhitespace(name)
            if name == previous { break }
        }

        return name.trimmingCharacters(in: providerSeparators)
    }

    public static func isPrimaryCategoryVisible(
        _ rawName: String?,
        rawID: String? = nil,
        provider: ContentCategoryProvider = .unknown,
        contentType: ContentType
    ) -> Bool {
        normalize(rawID: rawID, rawName: rawName, provider: provider, contentType: contentType).isPrimaryVisible
    }

    public static func hub(for categoryName: String) -> BrandHub {
        let normalized = normalize(
            rawName: categoryName,
            provider: .unknown,
            contentType: .movie
        )
        let name = "\(categoryName) \(normalized.displayName)".lowercased()
        let tokens = Set(tokenized(name))

        if name.contains("netflix") || name.contains("ntx") || tokens.contains("nf") { return .netflix }
        if ["hbo", "max"].contains(where: { name.contains($0) }) { return .hbo }
        if ["apple", "atvp"].contains(where: { name.contains($0) }) { return .apple }
        if ["disney", "dsnp", "marvel", "star wars"].contains(where: { name.contains($0) }) { return .disney }
        if ["amazon", "prime", "amz"].contains(where: { name.contains($0) }) { return .amazon }
        if ["anime", "crunchyroll", "crt"].contains(where: { name.contains($0) }) { return .anime }
        if ["kids", "dzieci", "bajki", "family", "children", "animacj"].contains(where: { name.contains($0) }) { return .kids }
        if ["polska", "polski", "polskie", "filmy", "kino", "seriale"].contains(where: { name.contains($0) }) { return .poland }
        return .other
    }

    // MARK: - Private

    private static let providerSeparators = CharacterSet(charactersIn: " \t\r\n|-:•·>/\\")
    private static let noiseTokens = ["vip", "premium", "backup", "zapasowe", "test", "trial"]
    private static let languageTokens = ["pl", "en", "de", "fr", "it", "es", "tr", "ru", "uk", "us", "nl", "ro", "ar"]
    private static let qualityTokens = ["4k", "uhd", "fhd", "hd", "sd", "1080p", "720p", "hevc", "h265", "h264"]

    private static let prefixTokenPattern =
        #"(?i)^(?:PL|EN|DE|FR|IT|ES|TR|RU|UK|US|NL|RO|AR|VOD|MOVIES?|FILMS?|SERIES|TV|VIP|PREMIUM|BACKUP|ZAPASOWE|TEST|4K|UHD|FHD|HD|SD|1080P|720P|HEVC|H265|H264)\b[\s\|\-:•·>/\\]*"#
    private static let suffixTokenPattern =
        #"(?i)[\s\|\-:•·>/\\]*(?:PL|EN|DE|FR|IT|ES|TR|RU|UK|US|NL|RO|AR|VOD|VIP|PREMIUM|BACKUP|ZAPASOWE|TEST|4K|UHD|FHD|HD|SD|1080P|720P|HEVC|H265|H264)\b$"#

    private static func category(
        raw: RawProviderCategory,
        displayName: String,
        role: ContentCategoryRole,
        priority: Int,
        isPrimaryVisible: Bool,
        reasons: [ContentCategoryNoiseReason]
    ) -> NormalizedContentCategory {
        let safeDisplay = collapseWhitespace(displayName).isEmpty ? "Other" : collapseWhitespace(displayName)
        let keyBasis = slugify(safeDisplay).isEmpty ? slugify(raw.rawID ?? "unknown") : slugify(safeDisplay)
        let stableKey = "\(role.rawValue).\(keyBasis.isEmpty ? "unknown" : keyBasis)"
        return NormalizedContentCategory(
            raw: raw,
            displayName: safeDisplay,
            stableKey: stableKey,
            role: role,
            priority: priority,
            isPrimaryVisible: isPrimaryVisible,
            noiseReasons: reasons
        )
    }

    private static func roleForDisplayName(_ displayName: String, contentType: ContentType) -> ContentCategoryRole {
        let name = displayName.lowercased()
        if platformDisplayName(from: name) != nil { return .platform }
        if languageTokens.contains(name) { return .language }
        if qualityTokens.contains(name) { return .quality }
        if genreDisplayName(from: name, contentType: contentType) != nil { return .genre }
        return .providerFallback
    }

    private static func canonicalDisplayName(for displayName: String, contentType: ContentType) -> String {
        let name = displayName.lowercased()
        if let platform = platformDisplayName(from: name) { return platform }
        if let genre = genreDisplayName(from: name, contentType: contentType) { return genre }
        return displayName
    }

    private static func priorityForRole(
        _ role: ContentCategoryRole,
        reasons: [ContentCategoryNoiseReason]
    ) -> Int {
        let base: Int
        switch role {
        case .platform:
            base = 100
        case .genre:
            base = 200
        case .language:
            base = 650
        case .providerFallback:
            base = 700
        case .quality:
            base = 850
        case .providerNoise:
            base = 950
        case .adult, .hidden:
            base = 1_000
        }
        return reasons.isEmpty ? base : min(base + 100, 990)
    }

    private static func noiseReasons(in value: String) -> [ContentCategoryNoiseReason] {
        let name = value.lowercased()
        var reasons: [ContentCategoryNoiseReason] = []
        if name.contains("xxx") || name.contains("adult") || name.contains("18+") || name.contains("for adults") {
            reasons.append(.adult)
        }
        if name.contains("vip") { reasons.append(.vip) }
        if name.contains("premium") { reasons.append(.premium) }
        if name.contains("backup") || name.contains("zapasowe") { reasons.append(.backup) }
        if name.contains("test") || name.contains("trial") { reasons.append(.test) }
        if containsArabicScript(value) { reasons.append(.arabicScript) }
        if isNumericOnly(value) { reasons.append(.numericOnly) }
        return reasons
    }

    private static func isAdultCategory(_ value: String) -> Bool {
        let name = value.lowercased()
        return name.contains("xxx") || name.contains("adult") || name.contains("18+") || name.contains("for adults")
    }

    private static func isProviderNoiseOnly(_ value: String) -> Bool {
        let tokens = tokenized(value)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { noiseTokens.contains($0) }
    }

    private static func isQualifierOnly(_ value: String) -> Bool {
        let tokens = tokenized(value)
        guard !tokens.isEmpty else { return false }
        let qualifiers = Set(noiseTokens + languageTokens + qualityTokens)
        return tokens.allSatisfy { qualifiers.contains($0) }
    }

    private static func isQualityOnly(_ value: String) -> Bool {
        let tokens = tokenized(value)
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { qualityTokens.contains($0) }
    }

    private static func isLanguageOnly(_ value: String) -> Bool {
        let tokens = tokenized(value)
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { languageTokens.contains($0) }
    }

    private static func isNumericOnly(_ value: String) -> Bool {
        let trimmed = collapseWhitespace(value)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func containsArabicScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(Int(scalar.value)) ||
            (0x0750...0x077F).contains(Int(scalar.value)) ||
            (0x08A0...0x08FF).contains(Int(scalar.value))
        }
    }

    private static func canonicalQualityName(_ value: String) -> String {
        let tokens = tokenized(value)
        if tokens.contains("4k") || tokens.contains("uhd") { return "4K" }
        if tokens.contains("fhd") || tokens.contains("1080p") { return "1080p" }
        if tokens.contains("hd") || tokens.contains("720p") { return "720p" }
        return value.uppercased()
    }

    private static func qualifierReasons(
        for value: String,
        existing reasons: [ContentCategoryNoiseReason]
    ) -> [ContentCategoryNoiseReason] {
        let tokens = tokenized(value)
        var result = reasons
        if tokens.contains(where: { languageTokens.contains($0) }) {
            result = appendUnique(.languageOnly, to: result)
        }
        if tokens.contains(where: { qualityTokens.contains($0) }) {
            result = appendUnique(.qualityOnly, to: result)
        }
        if tokens.contains(where: { noiseTokens.contains($0) }) {
            result = appendUnique(.providerNoise, to: result)
        }
        return result
    }

    private static func stripEdgeToken(from value: String, pattern: String) -> String {
        value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: providerSeparators)
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = collapseWhitespace(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func tokenized(_ value: String) -> [String] {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return folded
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func slugify(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let replaced = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func platformDisplayName(from lowercased: String) -> String? {
        if lowercased.contains("netflix") || lowercased == "nf" || lowercased.contains("ntx") { return "Netflix" }
        if lowercased.contains("hbo") || lowercased.contains("max") { return "Max" }
        if lowercased.contains("apple") || lowercased.contains("atvp") { return "Apple TV+" }
        if lowercased.contains("disney") || lowercased.contains("dsnp") { return "Disney+" }
        if lowercased.contains("amazon") || lowercased.contains("prime") || lowercased.contains("amz") { return "Prime Video" }
        return nil
    }

    private static func genreDisplayName(from lowercased: String, contentType: ContentType) -> String? {
        if lowercased.contains("kids") || lowercased.contains("dzieci") || lowercased.contains("bajki") ||
            lowercased.contains("family") || lowercased.contains("children") || lowercased.contains("animacj") {
            return "Family & Kids"
        }
        if lowercased.contains("docu") || lowercased.contains("dokument") { return "Documentaries" }
        if lowercased.contains("akcj") || lowercased.contains("action") { return "Action" }
        if lowercased.contains("komedi") || lowercased.contains("comedy") { return "Comedy" }
        if lowercased.contains("dramat") || lowercased.contains("drama") { return "Drama" }
        if lowercased.contains("horror") || lowercased.contains("thriller") || lowercased.contains("grozy") {
            return "Horror & Thriller"
        }
        if lowercased.contains("scifi") || lowercased.contains("sci-fi") ||
            lowercased.contains("fantasy") || lowercased.contains("s-f") {
            return "Sci-Fi & Fantasy"
        }
        if lowercased.contains("sport") { return "Sports" }
        if contentType == .liveTV && lowercased.contains("news") { return "News" }
        return nil
    }

    private static func appendUnique(
        _ reason: ContentCategoryNoiseReason,
        to reasons: [ContentCategoryNoiseReason]
    ) -> [ContentCategoryNoiseReason] {
        reasons.contains(reason) ? reasons : reasons + [reason]
    }
}
