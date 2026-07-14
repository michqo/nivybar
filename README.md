# NivyBar

A native macOS menu bar app that scrapes daily lunch menus from three restaurants near Nivy, Bratislava — and shows them in a clean dropdown without opening a browser.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## What it does

Click the fork icon in your menu bar → see today's soup and main dishes from:

| Restaurant | Zone |
|---|---|
| **Nostalgia Nivy** | Paričkova / Dulovo nám. |
| **Pivovar Komín** | Miletičova (Trhovisko) |
| **Dulák Košická** | Košická / Dulovo nám. |

Menus are cached locally so the app loads instantly on reopen. A new scrape only fires when the cached data is from a previous day, or when you hit **Refresh** manually.

---

## Features

- **Native SwiftUI** — `MenuBarExtra` with `.window` style, no Dock icon
- **Local HTML scraping** — `URLSession` + `SwiftSoup`, no third-party API
- **Smart caching** — JSON saved to `Application Support/NivyBar/`, stale-checked by date
- **Concurrent fetching** — all three restaurants scraped in parallel with `async let`
- **Per-restaurant error isolation** — one failure doesn't block the others
- **Weekend aware** — no pointless network requests on Sat/Sun
- **Dark & Light mode** — native adaptive colors throughout

---

## Stack

- Swift / SwiftUI
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) — HTML parsing
- `URLSession` with Safari User-Agent header
- `MenuBarExtra` (macOS 13+)
- App Sandbox with outgoing network connections only

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+
- Apple Developer account (free Personal Team works for local use)

---

## Setup

```bash
git clone https://github.com/your-username/NivyBar.git
cd NivyBar
open NivyBar.xcodeproj
```

SwiftSoup is already added as a Swift Package dependency — Xcode will resolve it on first open.

Select your team in **Signing & Capabilities**, hit **Run**.

---

## Project structure

```
NivyBar/
├── NivyBarApp.swift          # @main, MenuBarExtra entry point
├── Models.swift              # MenuItem, RestaurantMenu, CachedMenuData
├── LocalCacheManager.swift   # Read/write JSON cache, staleness check
├── MenuScraper.swift         # URLSession fetch + SwiftSoup parsers (×3)
├── MenuViewModel.swift       # @MainActor state, async/await orchestration
└── ContentView.swift         # SwiftUI views — cards, rows, header, footer
```

---

## License

MIT
