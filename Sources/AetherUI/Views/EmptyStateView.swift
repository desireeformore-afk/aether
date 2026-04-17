import SwiftUI

/// Generic empty state — works on all platforms.
public struct EmptyStateView: View {
    public let title: String
    public let systemImage: String
    public var message: String? = nil

    public init(title: String, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
