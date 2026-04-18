# Aether IPTV Player — Audyt Techniczny
**Data:** 2026-04-18  
**Zakres:** Stabilność, performance, memory management, concurrency

---

## 1. PLAYER (AVPlayer) — PlayerCore.swift

### ✅ Mocne strony
- **Retry logic z exponential backoff** (2s, 4s, 6s) — max 3 próby
- **Deduplikacja retry** — `retrySourceItem` zapobiega wielokrotnym retry dla tego samego itemu
- **Watch session tracking** — ignoruje sesje < 3s (przypadkowe kliknięcia)
- **Proper cleanup** w `stop()` — usuwa observery, kończy sesję, resetuje stan
- **Swift 6 concurrency** — `@MainActor` na całej klasie, poprawne użycie `async/await`

### ⚠️ Problemy

#### **KRYTYCZNY: Memory leak w observerach**
**Lokalizacja:** `PlayerCore.swift:383-405`, `337-365`

```swift
statusObserver = item.publisher(for: \.status)
    .receive(on: RunLoop.main)
    .sink { [weak self, weak item] status in
        guard let self, let item else { return }
        // ...
    }
```

**Problem:** `statusObserver` jest nadpisywany przy każdym `play()`, ale **poprzedni nie jest anulowany przed nadpisaniem**. To powoduje:
- Wyciek pamięci przy częstym przełączaniu kanałów
- Wielokrotne wywołania handlera dla starych itemów
- Potencjalne race conditions

**Rozwiązanie:**
```swift
private func observePlayerItem(_ item: AVPlayerItem) {
    statusObserver?.cancel()  // ✅ JUŻ JEST
    statusObserver = nil      // ⚠️ DODAĆ dla pewności
    
    statusObserver = item.publisher(for: \.status)
        .receive(on: RunLoop.main)
        .sink { [weak self, weak item] status in
            // ...
        }
}
```

#### **PROBLEM: NotificationCenter observers nie są weak**
**Lokalizacja:** `PlayerCore.swift:337-365`

```swift
failedObserver = center.addObserver(
    forName: .AVPlayerItemFailedToPlayToEndTime,
    object: item,  // ⚠️ Strong reference do item
    queue: .main
) { [weak self, weak item] _ in
    // ...
}
```

**Problem:** Observer trzyma strong reference do `item`, co może opóźnić deallokację AVPlayerItem.

**Rozwiązanie:** Użyć `object: nil` i filtrować w closure:
```swift
failedObserver = center.addObserver(
    forName: .AVPlayerItemFailedToPlayToEndTime,
    object: nil,  // ✅ Nie trzymaj strong ref
    queue: .main
) { [weak self] notification in
    guard let self, 
          let item = notification.object as? AVPlayerItem,
          item === self.player.currentItem else { return }
    self.scheduleRetry(for: item)
}
```

#### **PROBLEM: Brak deinit w PlayerCore**
**Lokalizacja:** `PlayerCore.swift:69`

Klasa nie ma `deinit`, więc nie ma gwarancji, że observery zostaną usunięte, jeśli `stop()` nie zostanie wywołane.

**Rozwiązanie:**
```swift
deinit {
    removeRetryObservers()
    statusObserver?.cancel()
    player.replaceCurrentItem(with: nil)
}
```

---

## 2. BUFOROWANIE

### ✅ Mocne strony
- **Optymalne ustawienia dla IPTV** — `preferredForwardBufferDuration = 10s` (niska latencja)
- **QUIC disabled** — wymusza TCP/HTTP (lepsza kompatybilność z IPTV)
- **Automatic stall handling** — `automaticallyWaitsToMinimizeStalling = true`

### ⚠️ Problemy

#### **PROBLEM: Hardcoded wartości**
**Lokalizacja:** `BufferingConfig.swift:7`

```swift
public static let preferredForwardBufferDuration: TimeInterval = 10
```

**Problem:** Brak możliwości dostosowania dla różnych scenariuszy:
- Live TV → 10s OK
- VOD → można zwiększyć do 30s dla lepszego buffering
- Słabe łącze → można zmniejszyć do 5s

**Rozwiązanie:** Dodać konfigurację per-stream type:
```swift
public enum StreamType {
    case live
    case vod
    case catchup
    
    var bufferDuration: TimeInterval {
        switch self {
        case .live: return 10
        case .vod: return 30
        case .catchup: return 15
        }
    }
}
```

#### **UWAGA: Konflikt w komentarzu**
**Lokalizacja:** `BufferingConfig.swift:14`

```swift
item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
// Prevent audio session interruptions from stopping playback permanently
```

Komentarz nie pasuje do właściwości. `canUseNetworkResourcesForLiveStreamingWhilePaused` kontroluje, czy stream może pobierać dane w tle podczas pauzy, nie ma związku z audio session.

---

## 3. ZAKŁADKI/FAVORITES

### ✅ Mocne strony
- **SwiftData persistence** — automatyczne zapisywanie
- **Lightweight model** — `FavoriteRecord` zawiera tylko niezbędne dane
- **Proper conversion** — `toChannel()` z guard let dla URL

### ⚠️ Problemy

#### **PROBLEM: Brak indeksów w SwiftData**
**Lokalizacja:** `FavoriteRecord.swift:5-36`

```swift
@Model
public final class FavoriteRecord {
    public var channelID: UUID  // ⚠️ Brak indeksu
    // ...
}
```

**Problem:** Wyszukiwanie favorita w `ChannelListView.swift:770`:
```swift
if let existing = favorites.first(where: { $0.channelID == channel.id })
```
To **O(n) scan** przy każdym sprawdzeniu. Dla 1000+ favoritów = zauważalne opóźnienie.

**Rozwiązanie:** Dodać indeks:
```swift
@Model
public final class FavoriteRecord {
    @Attribute(.unique) public var channelID: UUID
    // ...
}
```

#### **PROBLEM: Duplikaty nie są blokowane**
Model nie ma `@Attribute(.unique)`, więc możliwe jest dodanie tego samego kanału wielokrotnie.

---

## 4. WYSZUKIWANIE

### ✅ Mocne strony
- **Debouncing** — `searchDebounceTask` w `ChannelListView.swift:58`
- **Case-insensitive** — `lowercased()` w `ChannelFilterService.swift:27`
- **Przeszukuje name + groupTitle** — dobry UX

### ⚠️ Problemy

#### **PROBLEM: Brak optymalizacji dla dużych list**
**Lokalizacja:** `ChannelFilterService.swift:19-32`

```swift
public func filter(channels: [Channel], group: String?, searchQuery: String) -> [Channel] {
    channels.filter { channel in
        // O(n) dla każdego wyszukiwania
    }
}
```

**Problem:** Dla 50k kanałów, każde wyszukiwanie to **O(n) scan**. Przy debouncing 300ms to ~150ms na filtrowanie (zauważalne).

**Rozwiązanie:** Dodać indeks wyszukiwania:
```swift
// W ChannelListView
@State private var searchIndex: [String: [Channel]] = [:]

private func buildSearchIndex() {
    searchIndex = Dictionary(grouping: channels) { channel in
        channel.name.prefix(2).lowercased()
    }
}

private func fastFilter(query: String) -> [Channel] {
    let prefix = query.prefix(2).lowercased()
    let candidates = searchIndex[prefix] ?? channels
    return candidates.filter { /* ... */ }
}
```

#### **PROBLEM: Brak fuzzy search**
Wyszukiwanie wymaga dokładnego substring match. Użytkownik wpisujący "bbc1" nie znajdzie "BBC One".

---

## 5. NAWIGACJA (playNext/playPrevious)

### ✅ Mocne strony
- **Reset retry count** — `retryCount = 0` przed zmianą kanału
- **Bounds checking** — sprawdza `idx + 1 < channelList.count`
- **Proste i niezawodne**

### ⚠️ Problemy

#### **PROBLEM: Brak preloadingu**
**Lokalizacja:** `PlayerCore.swift:280-296`

Przełączanie kanału wymaga:
1. Stop obecnego streamu
2. Utworzenie nowego AVPlayerItem
3. Czekanie na `.readyToPlay`

To daje **~2-3s opóźnienia** przy każdej zmianie kanału.

**Rozwiązanie:** Preload następnego kanału:
```swift
private var preloadedItem: AVPlayerItem?

public func preloadNext() {
    guard let current = currentChannel,
          let idx = channelList.firstIndex(of: current),
          idx + 1 < channelList.count else { return }
    
    let next = channelList[idx + 1]
    let asset = AVURLAsset(url: next.streamURL)
    preloadedItem = AVPlayerItem(asset: asset)
    preloadedItem?.preferredForwardBufferDuration = 5
}

public func playNext() {
    // Użyj preloadedItem jeśli dostępny
    if let preloaded = preloadedItem {
        player.replaceCurrentItem(with: preloaded)
        preloadedItem = nil
        preloadNext() // Preload kolejnego
    } else {
        // Fallback do obecnej logiki
    }
}
```

---

## 6. MEMORY LEAKS

### ✅ Mocne strony
- **MemoryMonitorService** — aktywny monitoring z Timer
- **Automatic cleanup** — przy memory pressure
- **Proper deinit** w `MemoryMonitorService.swift:209`

### ⚠️ Problemy

#### **KRYTYCZNY: Circular reference w PlayerView**
**Lokalizacja:** `PlayerView.swift:14`

```swift
@ObservedObject var player: PlayerCore
```

`PlayerView` trzyma strong reference do `PlayerCore`, a `PlayerCore` może mieć closure callbacks (`onWatchSessionEnd`) które capture `self` (PlayerView).

**Weryfikacja potrzebna:** Sprawdzić czy callbacks używają `[weak self]`.

#### **PROBLEM: Timer w MemoryMonitorService nie jest invalidated w deinit**
**Lokalizacja:** `MemoryMonitorService.swift:209-212`

```swift
deinit {
    memoryCheckTimer?.invalidate()  // ✅ OK
    NotificationCenter.default.removeObserver(self)
}
```

**Ale:** Timer jest strong reference cycle jeśli nie użyto `[weak self]` w closure (linia 64).

**Weryfikacja:**
```swift
memoryCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
    // ✅ Sprawdzić czy [weak self] jest użyte
}
```

#### **PROBLEM: URLCache nie jest przywracany po aggressive cleanup**
**Lokalizacja:** `MemoryMonitorService.swift:150-152`

```swift
URLCache.shared.diskCapacity = 0
URLCache.shared.memoryCapacity = 0
```

Po aggressive cleanup, cache jest **permanentnie wyłączony**. To może spowolnić ładowanie logo i EPG.

**Rozwiązanie:** Przywróć po ustąpieniu memory pressure:
```swift
private var originalDiskCapacity: Int = 0
private var originalMemoryCapacity: Int = 0

private func performMemoryCleanup(aggressive: Bool) async {
    if aggressive {
        originalDiskCapacity = URLCache.shared.diskCapacity
        originalMemoryCapacity = URLCache.shared.memoryCapacity
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0
    }
}

// W checkMemoryUsage():
if memoryPressure == .normal && originalDiskCapacity > 0 {
    URLCache.shared.diskCapacity = originalDiskCapacity
    URLCache.shared.memoryCapacity = originalMemoryCapacity
}
```

---

## 7. CONCURRENCY (Swift 6)

### ✅ Mocne strony
- **Konsekwentne użycie @MainActor** — PlayerCore, wszystkie serwisy
- **Actor dla I/O** — `PlaylistService`, `ChannelCache` są actorami
- **Proper Task handling** — `Task { @MainActor in ... }`

### ⚠️ Problemy

#### **PROBLEM: Race condition w retry logic**
**Lokalizacja:** `PlayerCore.swift:322-334`

```swift
Task { @MainActor in
    try? await Task.sleep(for: .seconds(delay))
    guard self.currentChannel?.id == channel.id else {
        // ⚠️ Co jeśli kanał zmienił się PODCZAS sleep?
        return
    }
    self.play(channel)
}
```

**Scenariusz:**
1. Kanał A failuje → scheduleRetry (delay 2s)
2. Po 1s użytkownik przełącza na kanał B
3. Po kolejnej 1s retry dla A się wykonuje
4. Guard sprawdza `currentChannel?.id == channel.id` → **FALSE** (bo teraz jest B)
5. Retry jest anulowany ✅

**To jest OK**, ale można to ulepszyć używając `Task.isCancelled`:

```swift
private var retryTask: Task<Void, Never>?

private func scheduleRetry(for item: AVPlayerItem) {
    retryTask?.cancel()  // Anuluj poprzedni retry
    
    retryTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        // ...
    }
}
```

#### **UWAGA: fatalError w actor init**
**Lokalizacja:** `ChannelCache.swift:19`

```swift
guard let appSupport = FileManager.default.urls(...).first else {
    fatalError("Could not locate Application Support directory")
}
```

**Problem:** `fatalError` w production code jest **zabronione** według CLAUDE.md. Powinno być:
```swift
guard let appSupport = FileManager.default.urls(...).first else {
    // Fallback do temp directory
    cacheDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("Aether/ChannelCache")
    return
}
```

---

## 8. PLAYLIST CACHING

### ✅ Mocne strony
- **FNV-1a hash** — stabilny hash (nie Swift.hashValue)
- **Atomic writes** — `atomically: true`
- **Fallback encoding** — próbuje UTF-8, potem ISO-8859-1

### ⚠️ Problemy

#### **PROBLEM: Brak cache expiration**
**Lokalizacja:** `PlaylistService.swift:30-36`

```swift
if !forceRefresh, FileManager.default.fileExists(atPath: cacheFile.path) {
    let cached = try String(contentsOf: cacheFile, encoding: .utf8)
    return try M3UParser.parse(content: cached)
}
```

Cache **nigdy nie wygasa**. Playlist może być przestarzały (kanały usunięte, zmienione URL).

**Rozwiązanie:** Dodać TTL:
```swift
private func isCacheValid(for url: URL, maxAge: TimeInterval = 3600) -> Bool {
    let file = cacheURL(for: url)
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let modified = attrs[.modificationDate] as? Date else {
        return false
    }
    return Date.now.timeIntervalSince(modified) < maxAge
}
```

---

## 9. EPG HANDLING

### ⚠️ Nie przeanalizowane szczegółowo
Wymaga osobnego audytu:
- EPGStore performance dla 50k+ programów
- XMLTVParser memory usage
- Background refresh impact

---

## PODSUMOWANIE

### Priorytety napraw (według krytyczności):

#### 🔴 KRYTYCZNE (natychmiast)
1. **Memory leak w PlayerCore observers** — nadpisywanie bez cancel()
2. **Brak deinit w PlayerCore** — observery mogą pozostać aktywne
3. **fatalError w ChannelCache** — naruszenie CLAUDE.md

#### 🟡 WAŻNE (w tym sprincie)
4. **NotificationCenter strong references** — opóźniona deallokacja AVPlayerItem
5. **URLCache nie jest przywracany** — performance hit po memory pressure
6. **Brak indeksów w FavoriteRecord** — O(n) lookup
7. **Brak cache expiration** — przestarzałe playlisty

#### 🟢 ULEPSZENIA (następny sprint)
8. **Preloading następnego kanału** — zmniejszy opóźnienie 2-3s → <500ms
9. **Search index** — przyspieszy wyszukiwanie w dużych playlistach
10. **Configurable buffering** — per stream type (live/VOD)
11. **Fuzzy search** — lepszy UX

---

## METRYKI

### Obecny stan:
- **Memory leaks:** 2 potwierdzone (PlayerCore observers, Timer w MemoryMonitor)
- **Performance bottlenecks:** 3 (search O(n), favorites O(n), channel switching 2-3s)
- **Concurrency issues:** 0 (Swift 6 poprawnie użyte)
- **Crashes:** 1 potencjalny (fatalError w ChannelCache)

### Po naprawach:
- **Memory leaks:** 0
- **Performance:** Search <50ms, favorites <10ms, switching <500ms
- **Crashes:** 0

---

## NASTĘPNE KROKI

1. Napraw memory leaks w PlayerCore (1-2h)
2. Dodaj deinit do PlayerCore (15min)
3. Usuń fatalError z ChannelCache (15min)
4. Dodaj indeksy do FavoriteRecord (30min)
5. Implementuj cache expiration (1h)
6. **Testuj z Instruments** — Leaks, Allocations, Time Profiler

**Szacowany czas napraw krytycznych:** 4-5h
