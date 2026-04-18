# Contributing to Aether

Thank you for your interest in contributing to Aether! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Coding Standards](#coding-standards)
- [Architecture Guidelines](#architecture-guidelines)

## Code of Conduct

This project follows a simple code of conduct:
- Be respectful and constructive
- Focus on what's best for the project
- Welcome newcomers and help them learn
- Assume good intentions

## Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Git
- Basic knowledge of Swift and SwiftUI

### Finding Issues to Work On

1. Check the [Issues](https://github.com/desireeformore-afk/aether/issues) page
2. Look for issues labeled `good first issue` or `help wanted`
3. Comment on the issue to let others know you're working on it
4. If you have a new idea, open an issue first to discuss it

## Development Setup

### Clone the Repository

```bash
git clone https://github.com/desireeformore-afk/aether.git
cd aether
```

### Open in Xcode

```bash
open Package.swift
```

Or use Xcode's File → Open and select the `aether` directory.

### Build and Run

1. Select the `AetherApp` scheme
2. Choose your target device (Mac)
3. Press ⌘R to build and run

### Running Tests

```bash
swift test
```

Or in Xcode: ⌘U

## Project Structure

```
aether/
├── Sources/
│   ├── AetherApp/          # macOS app target
│   │   ├── Views/          # SwiftUI views
│   │   ├── AetherApp.swift # App entry point
│   │   └── ...
│   ├── AetherCore/         # Core business logic
│   │   ├── Models/         # Data models
│   │   ├── Services/       # Business services
│   │   ├── Parsers/        # M3U/XMLTV parsers
│   │   ├── Player/         # PlayerCore
│   │   └── Storage/        # SwiftData models
│   ├── AetherUI/           # Shared UI components
│   ├── AetherTests/        # Unit tests
│   ├── AetherAppIOS/       # iOS app (future)
│   └── AetherAppTV/        # tvOS app (future)
├── USAGE.md                # User guide
├── CONTRIBUTING.md         # This file
└── README.md               # Project overview
```

### Module Responsibilities

- **AetherApp**: macOS-specific UI and app lifecycle
- **AetherCore**: Platform-agnostic business logic, parsers, services
- **AetherUI**: Reusable UI components and themes
- **AetherTests**: Unit and integration tests

## Making Changes

### Branching Strategy

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Use descriptive branch names:
   - `feature/add-recording` - New features
   - `fix/playback-crash` - Bug fixes
   - `docs/update-readme` - Documentation
   - `refactor/player-core` - Code refactoring
   - `test/epg-service` - Test additions

### Commit Messages

Follow conventional commits format:

```
type(scope): brief description

Longer explanation if needed.

Fixes #123
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test additions/changes
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `style`: Code style changes (formatting)
- `chore`: Build/tooling changes

**Examples:**
```
feat(player): Add Picture-in-Picture support

Implements PiP using AVPlayerView's native controls with
keyboard shortcut (P) and visual indicator.

Fixes #42
```

```
fix(epg): Handle missing program data gracefully

Prevents crash when EPG data is incomplete by adding
nil checks and default values.

Fixes #87
```

## Testing

### Writing Tests

- Place tests in `Sources/AetherTests/`
- Name test files with `Tests` suffix (e.g., `M3UParserTests.swift`)
- Use descriptive test names: `testBasicParse()`, `testEmptyContent()`
- Test both success and failure cases
- Use XCTest framework

**Example:**

```swift
import XCTest
@testable import AetherCore

final class MyFeatureTests: XCTestCase {
    func testFeatureBehavior() {
        // Arrange
        let input = "test data"
        
        // Act
        let result = MyFeature.process(input)
        
        // Assert
        XCTAssertEqual(result, "expected output")
    }
}
```

### Test Coverage

Aim for test coverage on:
- Parsers (M3U, XMLTV)
- Services (EPG, Playlist)
- Business logic in PlayerCore
- Data models and transformations

UI tests are welcome but not required.

## Submitting Changes

### Before Submitting

1. **Run tests**: Ensure all tests pass
   ```bash
   swift test
   ```

2. **Build successfully**: No compiler warnings
   ```bash
   swift build
   ```

3. **Format code**: Follow Swift style guidelines
   - Use 4 spaces for indentation
   - Follow existing code style
   - Add documentation comments for public APIs

4. **Update documentation**: If you changed public APIs or added features

### Pull Request Process

1. **Push your branch**:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Open a Pull Request** on GitHub:
   - Use a clear, descriptive title
   - Reference related issues (e.g., "Fixes #123")
   - Describe what changed and why
   - Include screenshots for UI changes
   - List any breaking changes

3. **PR Template**:
   ```markdown
   ## Description
   Brief description of changes
   
   ## Related Issues
   Fixes #123
   
   ## Changes Made
   - Added feature X
   - Fixed bug Y
   - Updated documentation
   
   ## Testing
   - [ ] Unit tests added/updated
   - [ ] Manual testing completed
   - [ ] No regressions found
   
   ## Screenshots (if applicable)
   [Add screenshots here]
   ```

4. **Review Process**:
   - Maintainers will review your PR
   - Address feedback and make requested changes
   - Once approved, your PR will be merged

## Coding Standards

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable and function names
- Prefer `let` over `var` when possible
- Use type inference where it improves readability
- Avoid force unwrapping (`!`) - use safe unwrapping

### SwiftUI Best Practices

- Keep views small and focused
- Extract complex views into separate components
- Use `@State` for view-local state
- Use `@ObservedObject` for external state
- Prefer composition over inheritance

### Documentation

Add documentation comments for public APIs:

```swift
/// Brief description of what this does.
///
/// Longer explanation if needed, including usage examples.
///
/// - Parameters:
///   - param1: Description of param1
///   - param2: Description of param2
/// - Returns: Description of return value
/// - Throws: Description of errors thrown
public func myFunction(param1: String, param2: Int) throws -> Result {
    // Implementation
}
```

### Error Handling

- Use Swift's error handling (`throws`, `try`, `catch`)
- Create custom error types when appropriate
- Provide meaningful error messages
- Don't silently swallow errors

### Concurrency

- Use Swift's modern concurrency (`async`/`await`)
- Mark actors with `@MainActor` when needed
- Avoid callback-based async patterns
- Use `Task` for background work

## Architecture Guidelines

### Separation of Concerns

- **Models**: Pure data structures (no business logic)
- **Services**: Business logic and external interactions
- **Views**: UI presentation only (minimal logic)
- **ViewModels**: Bridge between views and services (when needed)

### Dependency Injection

- Pass dependencies explicitly (avoid singletons)
- Use `@EnvironmentObject` for app-wide services
- Keep dependencies minimal and focused

### State Management

- Use SwiftData for persistent data (playlists, favorites)
- Use `@Published` properties in ObservableObjects
- Keep state as local as possible
- Avoid global mutable state

### Performance

- Use lazy loading for large lists
- Implement pagination for 1000+ items
- Cache expensive computations
- Profile before optimizing

### Accessibility

- Add accessibility labels to interactive elements
- Support VoiceOver
- Use semantic colors (not hardcoded)
- Test with accessibility features enabled

## Feature Development Workflow

### Adding a New Feature

1. **Plan**: Open an issue to discuss the feature
2. **Design**: Consider architecture and API design
3. **Implement**: Write code following guidelines
4. **Test**: Add unit tests and manual testing
5. **Document**: Update USAGE.md and add code comments
6. **Submit**: Open a PR with clear description

### Example: Adding a New Service

```swift
// 1. Define in AetherCore/Services/
import Foundation

/// Service for managing recordings.
///
/// Handles scheduling, storage, and playback of recorded streams.
public actor RecordingService {
    // Implementation
}

// 2. Add tests in AetherTests/
final class RecordingServiceTests: XCTestCase {
    func testRecordingCreation() {
        // Test implementation
    }
}

// 3. Integrate in AetherApp
@StateObject private var recordingService = RecordingService()

// 4. Update documentation
```

## Questions?

- Open an issue for questions
- Check existing issues and PRs
- Review the codebase for examples

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to Aether! 🎉
