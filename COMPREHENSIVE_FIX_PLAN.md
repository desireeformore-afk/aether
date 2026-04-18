# Comprehensive Aether Fix Plan

## Objective
Make Aether fully functional, clean, and Swift 6 compliant - no more patchwork fixes.

## Phase 1: Complete Swift 6 Concurrency Audit (CRITICAL)

### 1.1 Find ALL remaining @ObservedObject/@StateObject issues
- Scan entire AetherApp for any remaining old property wrappers
- Verify every View uses correct @State for @Observable services
- Check all @Environment vs @EnvironmentObject usage

### 1.2 Fix HTTPBypassProtocol Sendable issue
- Properly mark class as @unchecked Sendable or refactor
- Fix closure capture issues
- Ensure thread-safety

### 1.3 Verify all Services are properly @Observable
- Check every service in AetherCore/Services/
- Ensure no mixing of @Observable with ObservableObject
- Verify @MainActor placement is correct

### 1.4 Check for other concurrency issues
- Scan for non-Sendable captures
- Check actor isolation violations
- Verify async/await usage

## Phase 2: Build Verification

### 2.1 Clean build test
- Remove all DerivedData
- Build from scratch
- Verify ZERO errors, ZERO warnings

### 2.2 Multi-platform check
- Verify macOS target builds
- Check iOS/tvOS compatibility (if applicable)
- Ensure Package.swift is correct

## Phase 3: Functional Testing

### 3.1 Core functionality
- Player starts and plays streams
- Channel switching works
- EPG loads and displays
- Settings persist

### 3.2 Advanced features
- PiP works
- Recording functions
- Parental controls
- Theme switching
- Sleep timer

### 3.3 Edge cases
- Network errors handled gracefully
- Memory pressure handled
- Crash recovery works

## Phase 4: Code Quality

### 4.1 Remove dead code
- Find unused files
- Remove commented-out code
- Clean up imports

### 4.2 Documentation
- Ensure public APIs are documented
- Add missing comments for complex logic

### 4.3 Architecture review
- Check for circular dependencies
- Verify separation of concerns
- Ensure testability

## Execution Strategy

1. **Use Claude Code for systematic fixes** - not manual patching
2. **Test after each phase** - don't move forward with broken code
3. **Commit frequently** - small, focused commits
4. **Verify in Xcode** - ensure it actually builds and runs
5. **Document issues found** - learn from problems

## Success Criteria

✅ Builds with ZERO errors
✅ Builds with ZERO warnings  
✅ All features work in Xcode
✅ Code is clean and maintainable
✅ Swift 6 strict concurrency compliant
✅ No more "one more fix" cycles

## Timeline

- Phase 1: 30-45 minutes (thorough audit + fixes)
- Phase 2: 10 minutes (build verification)
- Phase 3: 20 minutes (functional testing plan)
- Phase 4: 15 minutes (cleanup)

Total: ~90 minutes for complete, working app

## Next Steps

1. Start with comprehensive scan of ALL Views
2. Generate complete list of issues
3. Fix systematically with Claude Code
4. Verify build
5. Report final status
