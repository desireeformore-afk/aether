import XCTest
@testable import AetherCore

final class AetherCoreTests: XCTestCase {
    func testPlaceholder() throws {
        XCTAssertTrue(true)
    }

    func testCategoryNormalizerCleansProviderNoiseButKeepsRawName() throws {
        let category = CategoryNormalizer.normalize(
            rawID: "42",
            rawName: "VIP | PL - 4K Action",
            provider: .xtream,
            contentType: .movie
        )

        XCTAssertEqual(category.raw.rawName, "VIP | PL - 4K Action")
        XCTAssertEqual(category.displayName, "Action")
        XCTAssertEqual(category.role, .genre)
        XCTAssertTrue(category.isPrimaryVisible)
        XCTAssertTrue(category.noiseReasons.contains(.vip))
    }

    func testCategoryNormalizerHidesAdultAndArabicPrimaryCategories() throws {
        let adult = CategoryNormalizer.normalize(
            rawName: "XXX Adults",
            provider: .m3u,
            contentType: .movie
        )
        let arabic = CategoryNormalizer.normalize(
            rawName: "أفلام عربية",
            provider: .xtream,
            contentType: .movie
        )

        XCTAssertFalse(adult.isPrimaryVisible)
        XCTAssertEqual(adult.role, .adult)
        XCTAssertFalse(arabic.isPrimaryVisible)
        XCTAssertTrue(arabic.noiseReasons.contains(.arabicScript))
    }

    func testCategoryNormalizerHidesQualityOnlyCategory() throws {
        let category = CategoryNormalizer.normalize(
            rawName: "FHD",
            provider: .m3u,
            contentType: .liveTV
        )

        XCTAssertEqual(category.displayName, "1080p")
        XCTAssertEqual(category.role, .quality)
        XCTAssertFalse(category.isPrimaryVisible)
    }

    func testCategoryNormalizerHidesMixedQualifierOnlyCategory() throws {
        let category = CategoryNormalizer.normalize(
            rawName: "VIP | PL - 4K",
            provider: .xtream,
            contentType: .movie
        )

        XCTAssertFalse(category.isPrimaryVisible)
        XCTAssertEqual(category.role, .providerNoise)
        XCTAssertTrue(category.noiseReasons.contains(.languageOnly))
        XCTAssertTrue(category.noiseReasons.contains(.qualityOnly))
    }

    func testXstreamVODResolvesCategoryIDToDisplayCategory() throws {
        let vod = XstreamVOD(
            id: 123,
            name: "Sample Movie",
            streamIcon: nil,
            categoryID: "42",
            categoryName: nil,
            containerExtension: "mp4",
            rating: nil
        )
        let category = CategoryNormalizer.normalize(
            rawID: "42",
            rawName: "VIP | PL - 4K Action",
            provider: .xtream,
            contentType: .movie
        )

        let resolved = vod.resolvingCategory(category)

        XCTAssertEqual(resolved.categoryID, "42")
        XCTAssertEqual(resolved.rawCategoryName, "VIP | PL - 4K Action")
        XCTAssertEqual(resolved.categoryName, "Action")
        XCTAssertEqual(resolved.normalizedCategory?.displayName, "Action")
    }

    func testChannelCacheDefaultsOldJSONContentTypeToLiveTV() throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Old Cached Channel",
            "streamURL": "http://example.com/live.ts",
            "logoURL": null,
            "groupTitle": "News",
            "epgId": "news"
          }
        ]
        """

        let cached = try JSONDecoder().decode([ChannelCache.CachedChannel].self, from: Data(json.utf8))
        XCTAssertEqual(cached[0].channel.contentType, .liveTV)
    }

    func testChannelCachePersistsContentType() throws {
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let streamURL = try XCTUnwrap(URL(string: "http://example.com/movie.mp4"))
        let channel = Channel(
            id: id,
            name: "Movie",
            streamURL: streamURL,
            groupTitle: "Movies",
            contentType: .movie
        )

        let data = try JSONEncoder().encode(ChannelCache.CachedChannel(channel))
        let cached = try JSONDecoder().decode(ChannelCache.CachedChannel.self, from: data)
        XCTAssertEqual(cached.channel.contentType, .movie)
    }
}
