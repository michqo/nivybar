# NivyBar

A native macOS menu bar app that scrapes daily lunch menus from restaurants near Nivy, Bratislava — and shows them in a clean dropdown without opening a browser.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## What it does

Click the fork icon in your menu bar → see today's soup and main dishes. Three restaurants are built in:

| Restaurant | Zone |
|---|---|
| **Nostalgia Nivy** | Paričkova / Dulovo nám. |
| **Pivovar Komín** | Miletičova (Trhovisko) |
| **Dulák Košická** | Košická / Dulovo nám. |

Add any other restaurant via Settings — the AI analyzes the page and generates CSS selectors automatically.

---

## Features

### Menu bar
- Native `MenuBarExtra` with `.window` style — no Dock icon, no Cmd+Tab entry
- Soup + main dishes per restaurant, with price where available
- Loading spinner during scrape, error card per restaurant on failure
- Manual Refresh button, "last updated" timestamp
- Weekend-aware — no network requests on Sat/Sun

### Dynamic restaurant management
- Add any restaurant URL via the ⚙ Settings window
- AI analyzes the page HTML and generates scraping selectors automatically
- Edit selectors manually if needed, test them live with the built-in tester
- Per-restaurant accent color, display name, zone label, favourite toggle
- Drag-to-reorder — controls where each restaurant appears in the list

### AI integration
- Connects to any LiteLLM-compatible endpoint via env vars
- Strips `<script>`, `<style>`, `<svg>`, `<noscript>` before sending — reduces token usage significantly
- HTML truncated to 30,000 chars before the API call
- Falls back to `r.jina.ai` for JavaScript-rendered pages
- Strict **20 calls/day** rate limit by default — prevents accidental token burn
- Live usage counter shown in Settings: `AI calls today: 3 / 20`

### Data & caching
- Menus cached to `Application Support/NivyBar/cached_menus.json`
- User restaurants persisted to `Application Support/NivyBar/user_restaurants.json`
- Cache stale-checked by date — one scrape per day unless forced
- All scrapers run concurrently; one failure never blocks the others

---

## Stack

- Swift / SwiftUI (macOS 13+)
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) — HTML parsing and stripping
- `URLSession` with Safari User-Agent
- `MenuBarExtra(.window)` + separate `Window` scene for Settings
- `NavigationSplitView` for the Settings UI
- LiteLLM-compatible API for AI selector generation
- App Sandbox — outgoing network connections only

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+
- Apple Developer account (free Personal Team works for local use)
- A LiteLLM-compatible API endpoint + key (optional — only needed for AI analysis of new restaurants)

---

## Setup

```bash
git clone https://github.com/your-username/NivyBar.git
cd NivyBar
open NivyBar.xcodeproj
```

SwiftSoup is already added as a Swift Package dependency — Xcode resolves it on first open.

Select your team in **Signing & Capabilities**, hit **Run**.

### AI configuration (optional)

Set these environment variables in Xcode (Product → Scheme → Edit Scheme → Run → Environment Variables):

| Variable | Required | Example |
|---|---|---|
| `OPENAI_BASE_URL` | Yes | `https://api.openai.com/v1` |
| `OPENAI_API_KEY` | Yes | `sk-...` |
| `OPENAI_MODEL` | No | `claude-sonnet-4-6` (default) |
| `NIVY_AI_DAILY_LIMIT` | No | `50` (default: 20) |

Any LiteLLM-compatible endpoint works — OpenAI, Anthropic, local Ollama, etc.

---

## Project structure

```
NivyBar/
├── NivyBarApp.swift            # @main, MenuBarExtra + Settings Window scenes
├── Models.swift                # MenuItem, RestaurantMenu, CachedMenuData
├── UserRestaurant.swift        # ScrapingRecipe, UserRestaurant, Color(hex:)
├── LocalCacheManager.swift     # JSON cache R/W, date staleness check
├── UserRestaurantStore.swift   # @MainActor store, debounced persistence
├── MenuScraper.swift           # Hardcoded scrapers for the 3 built-in restaurants
├── DynamicMenuScraper.swift    # SwiftSoup scraper driven by ScrapingRecipe
├── AIRecipeGenerator.swift     # HTML fetch → strip → LLM → ScrapingRecipe + rate limiter
├── MenuViewModel.swift         # @MainActor state, merges hardcoded + dynamic results
├── ContentView.swift           # Menu bar panel UI
├── SettingsView.swift          # NavigationSplitView — restaurant list + recipe editor
├── AddRestaurantSheet.swift    # Add restaurant + trigger AI analysis
└── RecipeTesterSheet.swift     # Live selector test with parsed result preview
```

---

## License

MIT
