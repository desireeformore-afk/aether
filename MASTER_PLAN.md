# AETHER PLAYER - MASTER PLAN
## Autonomous Development Session

**GOAL:** Działający IPTV player z proper UI i stabilnym streamingiem

**CURRENT STATE:**
- ❌ App nie pokazuje okna (brak bundle ID w SPM)
- ❌ Streamy nie ładują (HTTPBypassProtocol zarejestrowany ale app nie ma proper bundle)
- ❌ UI "ciasny" - nie wygląda jak player
- ✅ HTTPBypassProtocol.registerClass() w PlayerCore.init() ✓
- ✅ Kod kompiluje się ✓

---

## PHASE 1: XCODE PROJECT GENERATION (Priority: CRITICAL)
**Blocker:** Linux environment, XcodeGen requires macOS

### Task 1.1: GitHub Actions Workaround
- [ ] Create `.github/workflows/generate-xcode.yml`
- [ ] macOS runner: install XcodeGen, run `xcodegen generate`
- [ ] Commit generated .xcodeproj back to repo
- [ ] Trigger: manual workflow_dispatch
- **Time:** 30 min
- **Deliverable:** Working Aether.xcodeproj in repo

### Task 1.2: Verify Project Structure
- [ ] Check .xcodeproj was committed
- [ ] Verify 3 targets exist (macOS/iOS/tvOS)
- [ ] Verify Info.plist linked correctly
- [ ] Verify bundle IDs set
- **Time:** 10 min

---

## PHASE 2: PLAYER CORE FIXES (Priority: HIGH)

### Task 2.1: HTTPBypassProtocol Verification
- [ ] Read HTTPBypassProtocol.swift implementation
- [ ] Verify canInit() logic
- [ ] Verify startLoading() handles HTTP correctly
- [ ] Check if NSAllowsArbitraryLoads is needed (already in Info.plist ✓)
- **Time:** 20 min

### Task 2.2: Player Error Handling
- [ ] Review PlayerCore error states
- [ ] Add detailed logging for -1022 errors
- [ ] Implement fallback for failed streams
- [ ] Test retry logic
- **Time:** 30 min

### Task 2.3: Stream Testing
- [ ] Create test script with real IPTV URLs
- [ ] Test HTTP streams
- [ ] Test HTTPS streams
- [ ] Test HLS (.m3u8)
- **Time:** 20 min
- **Blocker:** Needs macOS to run app

---

## PHASE 3: UI OVERHAUL (Priority: MEDIUM)

### Task 3.1: Layout Redesign
**Current:** Sidebar + small player
**Target:** Fullscreen player + overlay controls

- [ ] Analyze current ChannelListView layout
- [ ] Design new layout (fullscreen player, floating channel list)
- [ ] Implement PlayerView as primary view
- [ ] Add overlay controls (play/pause, volume, channel info)
- **Time:** 2h

### Task 3.2: Channel Switching UX
- [ ] Keyboard shortcuts (↑↓ for channels, Space for play/pause)
- [ ] Quick channel picker (⌘K already exists, enhance it)
- [ ] Channel preview on hover
- **Time:** 1h

### Task 3.3: EPG Timeline Integration
- [ ] Review EPGTimeline component (if exists)
- [ ] Integrate with player view
- [ ] Show current/next program
- **Time:** 1.5h

---

## PHASE 4: POLISH & STABILITY (Priority: LOW)

### Task 4.1: Theme Engine
- [ ] Dark/Light mode toggle
- [ ] Persist theme preference
- [ ] Apply to all views
- **Time:** 30 min

### Task 4.2: Error States
- [ ] Proper error messages (not just logs)
- [ ] Retry UI for failed streams
- [ ] Loading indicators
- **Time:** 30 min

### Task 4.3: Performance
- [ ] Profile memory usage
- [ ] Check for leaks in AVPlayer
- [ ] Optimize channel list rendering
- **Time:** 30 min

---

## EXECUTION STRATEGY

### Parallel Workstreams:
1. **GitHub Actions** (can do now) → unblocks macOS testing
2. **Code Review** (can do now) → find bugs without running
3. **UI Redesign** (can do now) → prepare code, test later

### Blockers & Workarounds:
- **No macOS:** Use GitHub Actions for builds/tests
- **Can't run app:** Code review + static analysis
- **XcodeGen fails:** Manual .xcodeproj generation (last resort)

### Decision Points:
- If GitHub Actions fails → try manual .xcodeproj
- If HTTPBypassProtocol broken → try different ATS bypass
- If UI redesign too complex → incremental improvements

---

## SUCCESS CRITERIA

**MINIMUM (MVP):**
- [ ] App shows window on macOS
- [ ] Can load and play 1 HTTP stream
- [ ] Can switch channels

**TARGET (GOOD):**
- [ ] Stable playback (no crashes)
- [ ] Proper fullscreen UI
- [ ] Keyboard shortcuts work
- [ ] Error handling

**STRETCH (GREAT):**
- [ ] EPG timeline
- [ ] Theme switching
- [ ] iOS/tvOS builds work

---

## TIMELINE ESTIMATE

| Phase | Time | Can Start Now? |
|-------|------|----------------|
| 1. Xcode Project | 40 min | ✅ YES |
| 2. Player Core | 1h 10min | ✅ YES (review) |
| 3. UI Overhaul | 4h 30min | ✅ YES (code) |
| 4. Polish | 1h 30min | ✅ YES |
| **TOTAL** | **7h 50min** | |

**Realistic with blockers:** 10-12h

---

## COMMIT STRATEGY

- Commit after each completed task
- Push immediately (user requirement)
- Descriptive commit messages
- Tag major milestones

---

## UPDATE SCHEDULE

- Every 10 minutes via Telegram
- Format: "STATUS (Xmin): [what's done] [what's next]"
- Report blockers immediately
- Final summary when done

---

**START TIME:** Now
**EXPECTED COMPLETION:** 8-12h (autonomous)
**NEXT UPDATE:** 10 min
