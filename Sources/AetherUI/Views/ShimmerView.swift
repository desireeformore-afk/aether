import SwiftUI

/// A parametric skeleton loading placeholder with an animated shimmer sweep.
/// Use directly where a content shape is needed during loading.
///
/// Example:
/// ```swift
/// ShimmerView(width: 150, height: 14, cornerRadius: 4)
/// ShimmerView(height: 240, cornerRadius: 12) // full-width
/// ```
public struct ShimmerView: View {
    public var width: CGFloat?
    public var height: CGFloat
    public var cornerRadius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ShimmerShape(cornerRadius: cornerRadius)
            .frame(width: width, height: height)
    }
}

// MARK: - Skeleton row for ChannelRowView

/// A shimmer placeholder row that matches ChannelRowView's layout.
/// Drop-in loading state for channel lists.
public struct ChannelRowSkeletonView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ShimmerView(width: 40, height: 40, cornerRadius: 20)
            VStack(alignment: .leading, spacing: 5) {
                ShimmerView(width: 140, height: 14, cornerRadius: 4)
                ShimmerView(width: 90, height: 10, cornerRadius: 4)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
    }
}

// MARK: - Private shimmer shape

private struct ShimmerShape: View {
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1))
            .overlay(
                GeometryReader { _ in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .init(x: phase, y: 0),
                        endPoint: .init(x: phase + 0.5, y: 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}
