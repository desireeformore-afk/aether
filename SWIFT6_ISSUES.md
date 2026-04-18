# Swift 6 Compliance Issues - Complete Audit

**Date:** 2026-04-18  
**Project:** Aether IPTV Player  
**Status:** Phase 1 - Issue Identification Complete

---

## Summary

Total Issues Found: **11**
- P0 (Blocks Build): **11**
- P1 (Warnings): **0**

---

## P0 Issues - Must Fix

### 1. ThemeService - Mixed Observable Patterns (3 instances)

**File:** `Sources/AetherAppTV/AetherAppTV.swift`  
**Line:** 11  
**Current Code:**
```swift
@StateObject private var themeService = ThemeService()
```
**Required Fix:**
```swift
@State private var themeService = ThemeService()
```
**Reason:** ThemeService is @Observable, not ObservableObject. Must use @State.

---

**File:** `Sources/AetherAppTV/AetherAppTV.swift`  
**Line:** 20  
**Current Code:**
```swift
.environmentObject(themeService)
```
**Required Fix:**
```swift
.environment(themeService)
```
**Reason:** @Observable classes use .environment(), not .environmentObject()

---

**File:** `Sources/AetherAppIOS/AetherAppIOS.swift`  
**Line:** 11  
**Current Code:**
```swift
@StateObject private var themeService = ThemeService()
```
**Required Fix:**
```swift
@State private var themeService = ThemeService()
```
**Reason:** ThemeService is @Observable, not ObservableObject. Must use @State.

---

**File:** `Sources/AetherAppIOS/AetherAppIOS.swift`  
**Line:** 20  
**Current Code:**
```swift
.environmentObject(themeService)
```
**Required Fix:**
```swift
.environment(themeService)
```
**Reason:** @Observable classes use .environment(), not .environmentObject()

---

### 2. CloudKitManager - Mixed Observable Patterns (1 instance)

**File:** `Sources/AetherApp/Views/CloudSyncView.swift`  
**Line:** 5  
**Current Code:**
```swift
@StateObject private var cloudKit = CloudKitManager.shared
```
**Required Fix:**
```swift
@State private var cloudKit = CloudKitManager.shared
```
**Reason:** CloudKitManager is @Observable, not ObservableObject. Must use @State.

---

### 3. PlaylistSharingService - Mixed Observable Patterns (4 instances)

**File:** `Sources/AetherApp/Views/PlaylistSharingView.swift`  
**Line:** 5  
**Current Code:**
```swift
@StateObject private var sharingService = PlaylistSharingService()
```
**Required Fix:**
```swift
@State private var sharingService = PlaylistSharingService()
```
**Reason:** PlaylistSharingService is @Observable, not ObservableObject. Must use @State.

---

**File:** `Sources/AetherApp/Views/PlaylistSharingView.swift`  
**Line:** 163  
**Current Code:**
```swift
@ObservedObject var sharingService: PlaylistSharingService
```
**Required Fix:**
```swift
@Bindable var sharingService: PlaylistSharingService
```
**Reason:** For @Observable classes passed as parameters, use @Bindable for two-way binding.

---

**File:** `Sources/AetherApp/Views/PlaylistSharingView.swift`  
**Line:** 248  
**Current Code:**
```swift
@ObservedObject var sharingService: PlaylistSharingService
```
**Required Fix:**
```swift
@Bindable var sharingService: PlaylistSharingService
```
**Reason:** For @Observable classes passed as parameters, use @Bindable for two-way binding.

---

**File:** `Sources/AetherApp/Views/PlaylistSharingView.swift`  
**Line:** 393  
**Current Code:**
```swift
@ObservedObject var sharingService: PlaylistSharingService
```
**Required Fix:**
```swift
@Bindable var sharingService: PlaylistSharingService
```
**Reason:** For @Observable classes passed as parameters, use @Bindable for two-way binding.

---

**File:** `Sources/AetherApp/Views/PlaylistSharingView.swift`  
**Line:** 424  
**Current Code:**
```swift
@ObservedObject var sharingService: PlaylistSharingService
```
**Required Fix:**
```swift
@Bindable var sharingService: PlaylistSharingService
```
**Reason:** For @Observable classes passed as parameters, use @Bindable for two-way binding.

---

### 4. RecommendationService - Mixed Observable Patterns (1 instance)

**File:** `Sources/AetherApp/Views/RecommendationsView.swift`  
**Line:** 5  
**Current Code:**
```swift
@ObservedObject var recommendationService: RecommendationService
```
**Required Fix:**
```swift
@Bindable var recommendationService: RecommendationService
```
**Reason:** RecommendationService is @Observable. Use @Bindable for parameters.

---

### 5. TimeshiftService - Mixed Observable Patterns (1 instance)

**File:** `Sources/AetherApp/Views/RecordingControlsButton.swift`  
**Line:** 8  
**Current Code:**
```swift
@ObservedObject var timeshiftService: TimeshiftService
```
**Required Fix:**
```swift
@Bindable var timeshiftService: TimeshiftService
```
**Reason:** TimeshiftService is @Observable. Use @Bindable for parameters.

---

## Verification Checklist

- [x] Scanned all files in Sources/AetherApp/Views/
- [x] Scanned all files in Sources/AetherCore/Services/
- [x] Scanned all files in Sources/AetherCore/Player/
- [x] Scanned AetherAppTV and AetherAppIOS entry points
- [x] Identified all @ObservedObject usage
- [x] Identified all @StateObject usage
- [x] Identified all .environmentObject() usage
- [x] Identified all @Observable services
- [ ] HTTPBypassProtocol Sendable issue (needs investigation)

---

## Fix Strategy

### Phase 1: Fix ThemeService (Priority 1)
1. AetherAppTV.swift - Replace @StateObject → @State
2. AetherAppTV.swift - Replace .environmentObject() → .environment()
3. AetherAppIOS.swift - Replace @StateObject → @State
4. AetherAppIOS.swift - Replace .environmentObject() → .environment()

### Phase 2: Fix CloudKitManager
1. CloudSyncView.swift - Replace @StateObject → @State

### Phase 3: Fix PlaylistSharingService
1. PlaylistSharingView.swift line 5 - Replace @StateObject → @State
2. PlaylistSharingView.swift line 163 - Replace @ObservedObject → @Bindable
3. PlaylistSharingView.swift line 248 - Replace @ObservedObject → @Bindable
4. PlaylistSharingView.swift line 393 - Replace @ObservedObject → @Bindable
5. PlaylistSharingView.swift line 424 - Replace @ObservedObject → @Bindable

### Phase 4: Fix RecommendationService
1. RecommendationsView.swift - Replace @ObservedObject → @Bindable

### Phase 5: Fix TimeshiftService
1. RecordingControlsButton.swift - Replace @ObservedObject → @Bindable

### Phase 6: Verify Build
1. Check for any remaining errors
2. Run tests if available
3. Commit all changes

---

## Notes

- All services in AetherCore/Services/ are correctly marked as @Observable
- No ObservableObject conformance found on @Observable classes (good!)
- No @Published properties found in @Observable classes (good!)
- Main issue is inconsistent usage of property wrappers in Views
- HTTPBypassProtocol Sendable issue needs separate investigation

---

## Next Steps

1. Apply all fixes systematically in order
2. Test each phase
3. Commit after each logical group
4. Final verification build
