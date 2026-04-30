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

    func testCatalogBuilderGroupsProviderVariantsIntoOneMovie() throws {
        let vods = (0..<10).map { index in
            XstreamVOD(
                id: 1_000 + index,
                name: "Dune [\(index % 2 == 0 ? "PL DUB" : "EN")] [\(index % 3 == 0 ? "4K" : "HD")]",
                streamIcon: index == 0 ? "https://example.com/dune.jpg" : nil,
                categoryID: "42",
                categoryName: "Action",
                containerExtension: index % 2 == 0 ? "mp4" : "mkv",
                rating: "8.\(index)"
            )
        }

        let snapshot = CatalogBuilder.build(vods: vods, series: [])

        XCTAssertEqual(snapshot.vodItems.count, 1)
        XCTAssertEqual(snapshot.vodItems[0].title, "Dune")
        XCTAssertEqual(snapshot.vodItems[0].variants.count, 10)
        XCTAssertEqual(snapshot.vodItems[0].posterURLString, "https://example.com/dune.jpg")
    }

    func testCatalogVariantPriorityPrefersPolishDubBeforeQuality() throws {
        let english4K = XstreamVOD(
            id: 1,
            name: "Arrival [EN] [4K]",
            streamIcon: nil,
            categoryID: "1",
            categoryName: "Sci-Fi",
            containerExtension: "mp4",
            rating: nil
        )
        let polishSub = XstreamVOD(
            id: 2,
            name: "Arrival [PL SUB] [1080p]",
            streamIcon: nil,
            categoryID: "1",
            categoryName: "Sci-Fi",
            containerExtension: "mp4",
            rating: nil
        )
        let polishDubHD = XstreamVOD(
            id: 3,
            name: "Arrival [PL DUB] [720p]",
            streamIcon: nil,
            categoryID: "1",
            categoryName: "Sci-Fi",
            containerExtension: "mkv",
            rating: nil
        )

        let sorted = CatalogVariantSelector.sortedVODs([english4K, polishSub, polishDubHD])

        XCTAssertEqual(sorted.first?.id, polishDubHD.id)
        XCTAssertEqual(CatalogVariantSelector.variantLabel(for: polishDubHD), "PL DUB | 720p | MKV")
    }

    func testCatalogBuildsPremiumRailsAndGenreSections() throws {
        let vods = [
            XstreamVOD(
                id: 1,
                name: "Premium Movie [4K]",
                streamIcon: nil,
                categoryID: "a",
                categoryName: "Action",
                containerExtension: "mp4",
                rating: "9.1"
            ),
            XstreamVOD(
                id: 2,
                name: "Quiet Drama [PL]",
                streamIcon: nil,
                categoryID: "d",
                categoryName: "Drama",
                containerExtension: "mp4",
                rating: "7.0"
            )
        ]

        let snapshot = CatalogBuilder.build(vods: vods, series: [])

        XCTAssertTrue(snapshot.movieSections.contains { $0.title == "Top Rated" })
        XCTAssertTrue(snapshot.movieSections.contains { $0.title == "4K/HDR" })
        XCTAssertTrue(snapshot.movieGenres.contains("Action"))
        XCTAssertTrue(snapshot.movieGenres.contains("Drama"))
    }

    func testCatalogSearchUsesLocalUnifiedIndex() async throws {
        let index = CatalogIndex()
        let vods = [
            XstreamVOD(
                id: 1,
                name: "Blade Runner [PL DUB]",
                streamIcon: nil,
                categoryID: "1",
                categoryName: "Sci-Fi",
                containerExtension: "mp4",
                rating: nil
            )
        ]
        let series = [
            XstreamSeries(
                id: 2,
                name: "Runner Series",
                cover: nil,
                plot: nil,
                cast: nil,
                director: nil,
                genre: "Drama",
                releaseDate: "2026-01-01",
                rating: nil,
                categoryID: "2",
                categoryName: "Drama"
            )
        ]

        await index.update(vods: vods, series: series)
        let results = await index.search(query: "blade", limit: 10)

        XCTAssertEqual(results.movies.first?.title, "Blade Runner")
        XCTAssertTrue(results.series.isEmpty)
    }
}
