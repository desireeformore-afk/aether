import XCTest
@testable import AetherCore

enum PlayerCoreTestSupport {
    static var isGitHubActions: Bool {
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    }

    @MainActor
    static func makePlayerCore() throws -> PlayerCore {
        try XCTSkipIf(
            isGitHubActions,
            "Skipping VLCKit-backed PlayerCore tests on GitHub Actions because VLCMediaPlayer can abort the macOS runner."
        )
        return PlayerCore()
    }
}
