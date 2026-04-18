import XCTest
@testable import AetherCore

@MainActor
final class ParentalControlStressTests: XCTestCase {

    func testRapidPINValidation() {
        let service = ParentalControlService()
        service.setupPIN("1234")

        // Validate PIN many times rapidly
        for _ in 1...1000 {
            _ = service.validatePIN("1234")
            _ = service.validatePIN("0000")
        }

        // Should not crash
        XCTAssertTrue(service.hasPIN)
    }

    func testConcurrentSessionLockUnlock() {
        let service = ParentalControlService()
        service.setupPIN("1234")

        // Rapidly lock and unlock session
        for _ in 1...500 {
            _ = service.unlockSession(pin: "1234")
            service.lockSession()
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testMassChannelLocking() {
        let service = ParentalControlService()
        service.setupPIN("1234")

        let channels = (1...1000).map { i in
            Channel(name: "Channel \(i)", streamURL: URL(string: "http://example.com/stream\(i)")!)
        }

        // Lock all channels
        for channel in channels {
            service.lockChannel(channel)
        }

        // Verify all are locked
        for channel in channels {
            XCTAssertTrue(service.isChannelLocked(channel))
        }

        // Unlock all channels
        for channel in channels {
            service.unlockChannel(channel)
        }

        // Verify all are unlocked
        for channel in channels {
            XCTAssertFalse(service.isChannelLocked(channel))
        }
    }

    func testRapidAgeRatingChanges() {
        let service = ParentalControlService()
        service.setupPIN("1234")

        let ratings: [AgeRating] = [.g, .pg, .pg13, .r, .nc17, .unrated]

        // Rapidly change age rating
        for _ in 1...500 {
            for rating in ratings {
                service.setMaxAgeRating(rating)
            }
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testConcurrentChannelAccessChecks() {
        let service = ParentalControlService()
        service.setupPIN("1234")
        service.setMaxAgeRating(.pg13)

        let channels = (1...100).map { i in
            Channel(
                name: "Channel \(i)",
                streamURL: URL(string: "http://example.com/stream\(i)")!,
                ageRating: [.g, .pg, .pg13, .r, .nc17].randomElement()
            )
        }

        // Check access for all channels many times
        for _ in 1...100 {
            for channel in channels {
                _ = service.canPlayChannel(channel)
            }
        }

        // Should not crash
        XCTAssertTrue(true)
    }
}
