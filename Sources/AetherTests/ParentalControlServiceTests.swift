import XCTest
@testable import AetherCore

final class ParentalControlServiceTests: XCTestCase {
    var service: ParentalControlService!
    var userDefaults: UserDefaults!

    @MainActor
    override func setUp() async throws {
        userDefaults = UserDefaults(suiteName: "test.aether.parentalcontrols")!
        userDefaults.removePersistentDomain(forName: "test.aether.parentalcontrols")
        service = ParentalControlService(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: "test.aether.parentalcontrols")
        userDefaults = nil
        service = nil
    }

    // MARK: - PIN Management Tests

    @MainActor
    func testSetupPIN() throws {
        XCTAssertFalse(service.settings.isEnabled)
        XCTAssertNil(service.settings.pinHash)

        try service.setupPIN("1234")

        XCTAssertTrue(service.settings.isEnabled)
        XCTAssertNotNil(service.settings.pinHash)
    }

    @MainActor
    func testSetupPINInvalidLength() {
        XCTAssertThrowsError(try service.setupPIN("123")) { error in
            XCTAssertEqual(error as? ParentalControlError, .invalidPIN)
        }

        XCTAssertThrowsError(try service.setupPIN("12345")) { error in
            XCTAssertEqual(error as? ParentalControlError, .invalidPIN)
        }
    }

    @MainActor
    func testSetupPINNonNumeric() {
        XCTAssertThrowsError(try service.setupPIN("abcd")) { error in
            XCTAssertEqual(error as? ParentalControlError, .invalidPIN)
        }

        XCTAssertThrowsError(try service.setupPIN("12a4")) { error in
            XCTAssertEqual(error as? ParentalControlError, .invalidPIN)
        }
    }

    @MainActor
    func testValidatePIN() throws {
        try service.setupPIN("1234")

        XCTAssertTrue(service.validatePIN("1234"))
        XCTAssertTrue(service.isUnlocked)

        XCTAssertFalse(service.validatePIN("4321"))
        XCTAssertFalse(service.validatePIN("0000"))
    }

    @MainActor
    func testChangePIN() throws {
        try service.setupPIN("1234")

        try service.changePIN(current: "1234", new: "5678")

        XCTAssertTrue(service.validatePIN("5678"))
        XCTAssertFalse(service.validatePIN("1234"))
    }

    @MainActor
    func testChangePINIncorrectCurrent() throws {
        try service.setupPIN("1234")

        XCTAssertThrowsError(try service.changePIN(current: "0000", new: "5678")) { error in
            XCTAssertEqual(error as? ParentalControlError, .incorrectPIN)
        }
    }

    @MainActor
    func testResetPIN() throws {
        try service.setupPIN("1234")
        XCTAssertTrue(service.settings.isEnabled)

        try service.resetPIN()

        XCTAssertFalse(service.settings.isEnabled)
        XCTAssertNil(service.settings.pinHash)
        XCTAssertFalse(service.isUnlocked)
    }

    // MARK: - Session Management Tests

    @MainActor
    func testSessionUnlock() throws {
        try service.setupPIN("1234")
        XCTAssertFalse(service.isUnlocked)

        XCTAssertTrue(service.validatePIN("1234"))
        XCTAssertTrue(service.isUnlocked)
    }

    @MainActor
    func testSessionLock() throws {
        try service.setupPIN("1234")
        _ = service.validatePIN("1234")
        XCTAssertTrue(service.isUnlocked)

        service.lockSession()
        XCTAssertFalse(service.isUnlocked)
    }

    @MainActor
    func testSessionExtend() throws {
        try service.setupPIN("1234")
        _ = service.validatePIN("1234")
        XCTAssertTrue(service.isUnlocked)

        service.extendSession()
        XCTAssertTrue(service.isUnlocked)
    }

    // MARK: - Content Filtering Tests

    @MainActor
    func testChannelAllowedWhenDisabled() throws {
        let channel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            ageRating: .r
        )

        XCTAssertTrue(service.isChannelAllowed(channel))
    }

    @MainActor
    func testChannelAllowedWhenUnlocked() throws {
        try service.setupPIN("1234")
        _ = service.validatePIN("1234")

        let channel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            ageRating: .r
        )

        XCTAssertTrue(service.isChannelAllowed(channel))
    }

    @MainActor
    func testChannelBlockedByRating() throws {
        try service.setupPIN("1234")
        var settings = service.settings
        settings.maxAgeRating = .pg13
        try service.updateSettings(settings)

        let channel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            ageRating: .r
        )

        XCTAssertFalse(service.isChannelAllowed(channel))
    }

    @MainActor
    func testChannelAllowedByRating() throws {
        try service.setupPIN("1234")
        var settings = service.settings
        settings.maxAgeRating = .r
        try service.updateSettings(settings)

        let channel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            ageRating: .pg13
        )

        XCTAssertTrue(service.isChannelAllowed(channel))
    }

    @MainActor
    func testChannelBlockedByLock() throws {
        try service.setupPIN("1234")
        let channelId = UUID()
        try service.lockChannel(channelId)

        let channel = Channel(
            id: channelId,
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!
        )

        XCTAssertFalse(service.isChannelAllowed(channel))
    }

    @MainActor
    func testChannelUnlock() throws {
        try service.setupPIN("1234")
        let channelId = UUID()
        try service.lockChannel(channelId)

        let channel = Channel(
            id: channelId,
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!
        )

        XCTAssertFalse(service.isChannelAllowed(channel))

        try service.unlockChannel(channelId)
        XCTAssertTrue(service.isChannelAllowed(channel))
    }

    // MARK: - Time Restriction Tests

    @MainActor
    func testTimeRestrictionActive() {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        let restriction = TimeRestriction(
            startHour: hour,
            endHour: (hour + 1) % 24,
            maxAgeRating: .pg,
            daysOfWeek: [weekday]
        )

        XCTAssertTrue(restriction.isActive(at: now))
    }

    @MainActor
    func testTimeRestrictionInactive() {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        let restriction = TimeRestriction(
            startHour: (hour + 2) % 24,
            endHour: (hour + 3) % 24,
            maxAgeRating: .pg,
            daysOfWeek: [weekday]
        )

        XCTAssertFalse(restriction.isActive(at: now))
    }

    @MainActor
    func testTimeRestrictionCrossesMidnight() {
        let restriction = TimeRestriction(
            startHour: 22,
            endHour: 6,
            maxAgeRating: .pg,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7]
        )

        // Test at 23:00 (should be active)
        var components = DateComponents()
        components.hour = 23
        components.minute = 0
        let date1 = Calendar.current.date(from: components)!
        XCTAssertTrue(restriction.isActive(at: date1))

        // Test at 02:00 (should be active)
        components.hour = 2
        let date2 = Calendar.current.date(from: components)!
        XCTAssertTrue(restriction.isActive(at: date2))

        // Test at 12:00 (should be inactive)
        components.hour = 12
        let date3 = Calendar.current.date(from: components)!
        XCTAssertFalse(restriction.isActive(at: date3))
    }

    // MARK: - Block Reason Tests

    @MainActor
    func testGetBlockReasonForLockedChannel() throws {
        try service.setupPIN("1234")
        let channelId = UUID()
        try service.lockChannel(channelId)

        let channel = Channel(
            id: channelId,
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!
        )

        let reason = service.getBlockReason(for: channel)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("locked"))
    }

    @MainActor
    func testGetBlockReasonForRating() throws {
        try service.setupPIN("1234")
        var settings = service.settings
        settings.maxAgeRating = .pg
        try service.updateSettings(settings)

        let channel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            ageRating: .r
        )

        let reason = service.getBlockReason(for: channel)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("rating"))
    }

    @MainActor
    func testGetBlockReasonWhenAllowed() throws {
        try service.setupPIN("1234")
        _ = service.validatePIN("1234")

        let channel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            ageRating: .r
        )

        let reason = service.getBlockReason(for: channel)
        XCTAssertNil(reason)
    }

    // MARK: - Persistence Tests

    @MainActor
    func testSettingsPersistence() throws {
        try service.setupPIN("1234")
        var settings = service.settings
        settings.maxAgeRating = .pg13
        try service.updateSettings(settings)

        // Create new service instance with same UserDefaults
        let newService = ParentalControlService(userDefaults: userDefaults)

        XCTAssertTrue(newService.settings.isEnabled)
        XCTAssertEqual(newService.settings.maxAgeRating, .pg13)
        XCTAssertNotNil(newService.settings.pinHash)
    }
}
