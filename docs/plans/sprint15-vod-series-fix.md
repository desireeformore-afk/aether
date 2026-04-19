# Sprint 15 — VOD/Series Fix + UI Polish

**Goal:** Naprawić wczytywanie Movies/Series w panelu + poprawić UI

**Root causes:**
1. `HSplitView` w `embeddedLayout` nie ma `.frame(maxHeight: .infinity)` → collapse
2. `.searchable()` na `vodGrid` wymaga NavigationStack — nie działa w HSplitView
3. Karty 160px za duże na 420px szerokość (mieści się ~2 kolumny)
4. Lista kategorii bez podpisu, zbyt wąska (120-150px)

**Zasady (z AGENTS.md):**
- NIE dodawaj nowych funkcji
- Napraw to co nie działa
- Popraw wygląd istniejących widoków
- Jeden commit na krok

---

## KROK A — VODBrowserView: napraw embeddedLayout

**Plik:** `Sources/AetherApp/Views/VODBrowserView.swift`

**Zmiany:**
1. Usuń `HSplitView` → zastąp `HStack(spacing: 0)` z Divider
2. Lista kategorii: `frame(width: 140)` + `.listStyle(.plain)` + header "Kategorie"
3. Usuń `.searchable()` z `vodGrid` — dodaj prosty `TextField` nad gridem
4. Grid: `GridItem(.adaptive(minimum: 120))` (mniejsze karty = więcej w 280px)
5. Cały embeddedLayout: `.frame(maxWidth: .infinity, maxHeight: .infinity)`

**Przed:**
```swift
private var embeddedLayout: some View {
    HSplitView {
        List(selection: $selectedCategory) { ... }
            .frame(minWidth: 120, maxWidth: 150)
        vodGrid
    }
    .task { await loadCategories() }
}
```

**Po:**
```swift
private var embeddedLayout: some View {
    HStack(spacing: 0) {
        // Category rail
        VStack(spacing: 0) {
            Text("Kategorie")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()
            if isLoadingCategories {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedCategory) {
                    ForEach(categories) { cat in
                        Text(cat.name)
                            .font(.system(size: 12))
                            .tag(cat)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 140)
        .background(Color.aetherSurface)

        Divider()

        // Content + inline search
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Szukaj...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.aetherSurface)

            Divider()

            vodGridContent  // Grid bez .searchable()
        }
        .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: selectedCategory) { _, cat in
        guard let cat else { return }
        Task { await loadStreams(for: cat) }
    }
    .task { await loadCategories() }
    .sheet(item: $selectedVOD) { vod in
        VODDetailSheet(vod: vod, credentials: credentials, player: player)
    }
}
```

**Rename:** `vodGrid` → `vodGridContent` (bez `.searchable()`), usuń `.searchable()` z vodGrid.

---

## KROK B — SeriesBrowserView: to samo naprawienie

**Plik:** `Sources/AetherApp/Views/SeriesBrowserView.swift`

Identyczne zmiany co w VODBrowserView:
- `HSplitView` → `HStack(spacing: 0)`
- Header "Kategorie" nad listą
- `.listStyle(.plain)`
- Inline search TextField
- `.frame(maxWidth: .infinity, maxHeight: .infinity)` na całym embeddedLayout

---

## KROK C — VODCard: mniejsze karty

**Plik:** `Sources/AetherApp/Views/VODBrowserView.swift` (VODCard struct)

Grid: `GridItem(.adaptive(minimum: 110), spacing: 12)` zamiast `minimum: 160`
Karta: `frame(width: 110, height: 165)` zamiast `160 x 240`
Padding grid: `.padding(12)` zamiast `.padding(20)`

---

## KROK D — SeriesCard analogicznie

**Plik:** `Sources/AetherApp/Views/SeriesBrowserView.swift`

Identyczne zmiany wymiarów co Krok C.

---

## Kolejność implementacji

1. KROK A (VODBrowserView embeddedLayout) → git commit → test
2. KROK B (SeriesBrowserView embeddedLayout) → git commit → test  
3. KROK C + D (rozmiary kart) → jeden commit → test

Kajetan testuje po każdym kroku.
