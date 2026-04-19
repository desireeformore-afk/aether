# Aether — Agent Context

## Projekt
Premium macOS IPTV player w SwiftUI/AVFoundation.
Repo: https://github.com/desireeformore-afk/aether
Branch: main

## Workflow
- Hermes edytuje kod i pushuje na GitHub
- Użytkownik (Kajetan) robi `git pull` i testuje lokalnie w Xcode
- Błędy kompilacji Kajetan zgłasza przez Telegram — Hermes naprawia i ponownie pushuje
- **Nigdy nie pushujesz bez commit message opisującego zmianę**
- **Jeden krok naraz — czekasz na OK od Kajetana przed następnym**
- Raport co 15 minut: co zrobiłeś, co teraz robisz

## Kompilacja na Ubuntu (Hetzner)
`swift build` NIE zadziała bo projekt używa SwiftUI/AppKit/AVFoundation (Apple-only).
Możesz użyć `swiftc --parse [plik].swift` do sprawdzenia składni pojedynczego pliku.
Testy kompilacyjne robi Kajetan lokalnie w Xcode (Cmd+B).

## Używaj Claude Code
Do edycji plików używaj `claude` jako subagenta. Wywołanie ZAWSZE z flagą `--max-turns 80` żeby nie skończyć za wcześnie.

### Prawidłowe wywołanie Claude Code:
```bash
cd ~/aether && claude --max-turns 80 -p "ZADANIE: [opis zadania]. 
Plik do edycji: [nazwa pliku].
Po edycji sprawdź składnię: swiftc --parse Sources/AetherApp/Views/[plik].swift 2>&1 | head -20
Jeśli błędy — napraw je. Jeśli czysto — zakończ."
```

### Weryfikacja PRZED każdym git push (OBOWIĄZKOWE):
```bash
# Sprawdź składnię zmienionych plików
swiftc --parse [zmieniony_plik.swift] 2>&1 | head -20

# Dopiero jak nie ma błędów:
git add [zmieniony_plik]
git commit -m "feat/fix: [opis]"
git push
```

**NIE pushuj jeśli swiftc --parse zwraca błędy.**

## Architektura
```
Sources/
  AetherCore/           ← logika biznesowa (bez UI)
    Player/
      PlayerCore.swift       ← główny player (AVPlayer wraper)
      LocalHLSProxy.swift    ← lokalny HTTP proxy dla streamów przez ffmpeg
      StreamProxyLoader.swift
      BufferingConfig.swift
    Services/
      XstreamService.swift   ← Xstream Codes API (live, VOD, series)
      PlaylistService.swift  ← M3U parser i cache
      ChannelFilterService.swift
  AetherApp/            ← UI (SwiftUI, macOS only)
    Views/
      ContentView.swift           ← root view
      PlayerView.swift            ← główny player UI
      ChannelListView.swift       ← lista kanałów z filtrowaniem
      FloatingChannelPanel.swift  ← pływający panel z zakładkami
      VODBrowserView.swift        ← browser filmów VOD
      SeriesBrowserView.swift     ← browser seriali
      GlobalContentSearchView.swift ← wyszukiwarka
      SettingsView.swift
```

## Aktualny stan bugów
| Problem | Status |
|---|---|
| HTTP 400 na filmach | ✅ Fixed (ffmpeg user-agent VLC/3.0.20) |
| HEVC crash (h264_mp4toannexb) | ✅ Fixed (ffprobe detekcja + dynamiczny BSF) |
| -1004 Connection refused | ⚠️ AVPlayer retruje na stary port gdy FFmpeg padnie |
| -12753 timebase warnings | ⚠️ Normalne Apple internal warnings z HLS |
| GUI wygląd | ⚠️ Wymaga przebudowy — cel: Apple TV app quality |
| GlobalContentSearchView handleSelection | ❌ TODO — nic nie robi po kliknięciu |

## Priorytety (w tej kolejności)
1. **NIE dodawaj nowych funkcji** (iCloud, Watch Party, Social, Analytics, Crash Reports etc.)
2. Napraw to co nie działa
3. Popraw wygląd istniejących widoków

## Zasady kodowania
- Swift 6 concurrency — @MainActor na klasach UI, actor dla I/O
- Brak fatalError w production code — zawsze graceful fallback
- Brak force-unwrap (`!`) bez gwarancji
- Każda zmiana to osobny commit z opisem co i dlaczego

## Aktualny plan pracy (UI Overhaul)
### KROK 1 — VODBrowserView.swift
Nowe karty VOD: poster 2:3 ratio z AsyncImage + shimmer skeleton podczas ładowania.
Hover: gradient overlay z tytułem + rok + rating badge (⭐).
Kliknięcie: otwiera VODDetailSheet z posterem, tytułem, ratingiem, dużym Play button.
Uwaga: XstreamService NIE ma getVodInfo — tylko streamIcon + rating na liście.

### KROK 2 — SeriesBrowserView.swift
Identyczne karty. Kliknięcie otwiera istniejący SeriesDetailView.
Użyj pola `cover` z modelu XstreamSeries (już istnieje).

### KROK 3 — GlobalContentSearchView.swift
- handleSelection() jest TODO — napraw: VOD → play, Seria → SeriesDetailView
- Zmień na debounced filter (300ms) po stronie klienta zamiast ładowania całego katalogu
- Dodaj okładki (streamIcon / cover) do kart wyników

### KROK 4 — PlayerCore.swift (retry fix)
- Gdy retry wykryje zmianę kanału (currentChannel.id ≠ retryChannel.id) → abort
- Gdy FFmpeg/proxy zwróci błąd 400 → state = .error(...), NIE uruchamiaj kolejnego retry

### KROK 5 — FloatingChannelPanel.swift
- Playlist sidebar: 180px
- Content area: 420px
- Tab switch: .contentTransition(.opacity)
- Aktywny tab: capsule background zamiast full-width fill
