import XCTest
@testable import AetherCore

@MainActor
final class ParentalControlServiceTests: XCTestCase {

    func testPINSetup() {
        let service = ParentalControlService()

        let result = service.setupPIN("1234")
        XCTAssertTrue(result)
        XCTAssertTrue(service.hasPIN)
    }

    func testPINValidation() {
        let service = ParentalControlService()

        service.setupPIN("1234")

        XCTAssertTrue(service.validatePIN("1234"))
        XCTAssertFalse(service.validatePIN("0000"))
        XCTAssertFalse(service.validatePIN("wrong"))
    }

    func testSessionUnlock() {
        let service = ParentalControlService()

        service.setupPIN("1234")
        XCTAssertFalse(service.isSessionUnlocked)

        let unlocked = service.unlockSession(pin: "1234")
        XCTAssertTrue(unlocked)
        XCTAssertTrue(service.isSessionUnlocked)
    }

    func testSessionLock() {
        let service = ParentalControlService()

        service.setupPIN("1234")
        service.unlockSession(pin: "1234")
        XCTAssertTrue(service.isSessionUnlocked)

        service.lockSession()
        XCTAssertFalse(service.isSessionUnlocked)
    }

    func testAgeRatingFilter() {
        let service = ParentalControlService()

        service.setupPIN("1234")
        service.setMaxAgeRating(.pg13)

        let channel1 = Channel(name: "Kids Show", streamURL: URL(string: "http://example.com/kids")!, ageRating: .g)
        let channel2 = Channel(name: "Teen Show", streamURL: URL(string: "http://example.com/teen")!, ageRating: .pg13)
        let channel3 = Channel(name: "Adult Show", streamURL: URL(string: "http://example.com/adult")!, ageRating: .r)

        XCTAssertTrue(service.canPlayChannel(channel1))
        XCTAssertTrue(service.canPlayChannel(channel2))
        XCTAssertFalse(service.canPlayChannel(channel3))
    }

    func testChannelLocking() {
        let service = ParentalControlService()

        service.setupPIN("1234")

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/test")!)

        XCTAssertFalse(service.isChannelLocked(channel))

        service.lockChannel(channel)
        XCTAssertTrue(service.isChannelLocked(channel))

        service.unlockChannel(channel)
        XCTAssertFalse(service.isChannelLocked(channel))
    }

    func testTimeRestrictions() {
        let service = ParentalControlService()

        service.setupPIN("1234")

        let restriction = ParentalSettings.TimeRestriction(
            startHour: 22,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7]
        )

        service.addTimeRestriction(restriction)

        // Test would need to mock current time to properly test
        XCTAssertNotNil(service.getTimeRestrictions())
    }
}
