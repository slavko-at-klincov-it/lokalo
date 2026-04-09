# Lokalo — App Store Connect Metadata

Copy/paste these fields directly into App Store Connect → App Information / Localizable Information.

## Bundle ID
`com.slavkoklincov.lokal`

## Primary Language
German

---

## German (Deutsch) — Primary

### Name (max 30 chars)
```
Lokalo
```

### Subtitle (max 30 chars)
```
KI offline auf deinem iPhone
```
(28 chars)

### Promotional Text (max 170 chars — can update without re-review)
```
Sprachmodelle direkt aufs Handy laden und mit ihnen chatten. Inferenz läuft auf dem Gerät — kein Konto bei Lokalo, kein Lokalo-Backend.
```
(135 chars)

### Description (max 4000 chars)
```
Lokalo bringt Sprachmodelle wie Llama, Phi, Qwen und Gemma direkt auf dein iPhone — und führt sie komplett auf dem Gerät aus. Kein Konto bei Lokalo, kein Lokalo-Server, kein Backend. Es gibt schlicht nichts, was zwischen deinem Chat und deinem iPhone liegt.

Lade ein Modell einmal herunter und chatte offline. Standardmäßig verlässt nichts dein iPhone.

KURATIERTE MODELLE
Eine handverlesene Auswahl an kompakten Sprachmodellen, optimiert für die Hardware deines iPhones:
• Llama 3.2 1B & 3B Instruct (Meta)
• Qwen 2.5 0.5B & 1.5B Instruct, Qwen 3.5 0.8B (Alibaba)
• Phi-3.5 Mini & Phi-4 Mini (Microsoft)
• Gemma 2 2B, Gemma 3 1B & 4B (Google)
• SmolLM2 1.7B & SmolLM3 3B (Hugging Face)
• TinyLlama 1.1B Chat

Alle Modelle werden direkt von Hugging Face bezogen. Du wählst, welches du laden willst — die App speichert nichts vor.

NATIV. SCHNELL. PRIVAT.
Lokalo ist in SwiftUI geschrieben und nutzt llama.cpp mit Apple Metal Beschleunigung. Streaming-Antworten Token für Token, native iOS Optik, Light- und Dark-Mode, Dynamic Type, VoiceOver-tauglich.

WAS DU EINSTELLEN KANNST
• Temperatur, Top-p, Min-p, Max-Token Sampling
• System Prompt komplett anpassbar
• Mehrere Modelle parallel laden, jederzeit umschalten
• Konversationsverlauf lokal speichern und wieder löschen

OPTIONAL: EIGENE QUELLEN ANBINDEN
Wenn du willst, kannst du Lokalo Zugriff auf eigene Dateien geben — als Wissensbasis für Retrieval Augmented Generation (RAG):
• Lokale Ordner aus der Files-App
• GitHub Repositories (Read-Only)
• Google Drive Ordner (Read-Only)
• OneDrive / SharePoint Ordner (Read-Only)
• Eigene MCP-Server über HTTPS

Diese Verbindungen sind ausschließlich optional und werden direkt zwischen deinem iPhone und dem jeweiligen Anbieter hergestellt — nie über einen Lokalo-Server, weil es keinen gibt. Auth-Tokens speichert Lokalo ausschließlich in deinem iOS Keychain, ohne iCloud-Sync. Indizierung und Embedding-Berechnung laufen lokal auf deinem Gerät.

WAS LOKALO NICHT MACHT
• Kein Konto bei Lokalo, keine Anmeldung bei mir
• Kein Tracking, keine Analytics, keine Werbung
• Keine versteckten In-App-Käufe
• Kein Backend — Lokalo betreibt keine Server, die dich oder deine Daten sehen könnten

WIE VIEL SPEICHER BRAUCHE ICH?
Modelle sind zwischen 380 MB und 2.5 GB groß. Der Download läuft im Hintergrund mit Pause/Resume. Du löschst alles mit einem Wisch.

FÜR WEN
• Entwickler die mit lokalen LLMs experimentieren wollen
• Datenschutz-Bewusste die keiner Cloud trauen
• Reisende ohne stabile Internetverbindung
• Alle die wissen wollen wie sich on-device KI 2026 anfühlt

Lokalo läuft auf deinem iPhone und gehört nur dir.
```
(~2700 chars)

### Keywords (max 100 chars, comma-separated)
```
LLM,offline,KI,AI,chat,llama,gguf,phi,qwen,gemma,lokal,datenschutz,on-device,privat
```
(99 chars)

### Support URL
```
https://klincov.it/lokal/support
```

### Marketing URL
```
https://klincov.it/lokal
```

### Privacy Policy URL
```
https://klincov.it/lokal/privacy
```

### Category
- Primary: **Productivity**
- Secondary: **Developer Tools** (optional)

### Age Rating
- Frequent/Intense Mature/Suggestive Themes: None
- Frequent/Intense Profanity or Crude Humor: Infrequent/Mild (since LLMs can occasionally produce them)
- Unrestricted Web Access: No (the app doesn't open arbitrary URLs)
- Result: 17+ (recommended due to user-generated content via the LLM)

---

## English

### Subtitle (max 30 chars)
```
On-device AI for your iPhone
```
(28 chars)

### Promotional Text (max 170 chars)
```
Download language models straight to your phone and chat with them on-device. No Lokalo account, no Lokalo backend — Lokalo runs no servers that can see your data.
```
(163 chars)

### Description (max 4000 chars)
```
Lokalo brings language models like Llama, Phi, Qwen and Gemma straight to your iPhone — and runs them entirely on the device. No Lokalo account, no Lokalo server, no backend. There is simply nothing sitting between your chat and your iPhone.

Download a model once and chat offline. By default, nothing leaves your iPhone.

CURATED MODELS
A handpicked selection of compact language models optimized for iPhone hardware:
• Llama 3.2 1B & 3B Instruct (Meta)
• Qwen 2.5 0.5B & 1.5B Instruct, Qwen 3.5 0.8B (Alibaba)
• Phi-3.5 Mini & Phi-4 Mini (Microsoft)
• Gemma 2 2B, Gemma 3 1B & 4B (Google)
• SmolLM2 1.7B & SmolLM3 3B (Hugging Face)
• TinyLlama 1.1B Chat

All models come straight from Hugging Face. You choose what to download — the app caches nothing in advance.

NATIVE. FAST. PRIVATE.
Lokalo is built in SwiftUI and powered by llama.cpp with Apple Metal acceleration. Streaming responses token by token, native iOS look, light and dark mode, Dynamic Type, VoiceOver friendly.

WHAT YOU CAN TUNE
• Temperature, top-p, min-p, max tokens
• Custom system prompt
• Keep multiple models loaded, switch any time
• Local conversation history with one-tap clear

OPTIONAL: BRING YOUR OWN SOURCES
If you want, you can give Lokalo access to your own files — as a knowledge base for Retrieval Augmented Generation (RAG):
• Local folders from the Files app
• GitHub repositories (read-only)
• Google Drive folders (read-only)
• OneDrive / SharePoint folders (read-only)
• Your own MCP servers over HTTPS

These connections are entirely optional and flow directly between your iPhone and the provider you choose — never through a Lokalo server, because there isn't one. Auth tokens live exclusively in your iOS Keychain, with no iCloud sync. Indexing and embedding all run locally on your device.

WHAT LOKALO DOES NOT DO
• No Lokalo account, no sign-up with us
• No tracking, no analytics, no ads
• No hidden in-app purchases
• No backend — Lokalo runs no servers that can see you or your data

HOW MUCH STORAGE
Models range from 380 MB to 2.5 GB. Downloads run in the background with pause/resume. Sweep to delete.

WHO IT'S FOR
• Developers experimenting with local LLMs
• Privacy-aware people who don't trust the cloud
• Travelers without stable connectivity
• Anyone curious how on-device AI feels in 2026

Lokalo runs on your iPhone and belongs only to you.
```

### Keywords (max 100 chars)
```
LLM,offline,AI,chat,llama,gguf,phi,qwen,gemma,local,private,on-device,rag,mcp
```

---

## What's New (for v1.0)
```
Erste Version! Lokalo bringt lokale Sprachmodelle aufs iPhone:
• 13 kuratierte GGUF-Modelle direkt von Hugging Face
• Streaming Chat mit Apple Metal Beschleunigung
• Inferenz läuft komplett auf dem Gerät — kein Lokalo-Backend
• Optional: eigene Quellen aus Files, GitHub, Drive oder OneDrive für RAG
• Native SwiftUI, Light + Dark Mode
• Anpassbare Sampling-Parameter und System Prompt
```

## App Review Information — Reviewer Notes

Paste this into App Store Connect → App Review Information → Notes (English, since reviewers default to English).

```
Lokalo runs language models entirely on the device. There is no Lokalo backend, no central account, and no Lokalo-operated OAuth app.

CORE FLOW (zero setup, what you most likely want to test):
1. Launch the app — onboarding plays a 5-second intro animation, then a settings screen ("Personalisieren"). Tap "Loslegen".
2. The library opens with the recommended first model preselected (Qwen 2.5 0.5B Instruct, ~380 MB Q4_K_M). Tap "Herunterladen".
3. Download takes ~30 seconds on Wi-Fi. After it completes, tap the model in the library to load it.
4. The Chat view opens. Type any prompt and tap send. Streaming response runs entirely on-device via llama.cpp + Apple Metal. No network call is made during inference.

OPTIONAL FEATURES (require user setup):

A) RAG with local files — works with no setup.
   Chat → top-right "books" icon → Wissen → tap "+" → "Ordner aus Files-App". Pick any folder. Lokalo will download a small embedding model on first use (~85 MB) and index the folder locally.

B) RAG with cloud sources (GitHub / Google Drive / OneDrive) — requires the user to register their own OAuth app.
   By design, Lokalo has no central OAuth client because that would require a Lokalo backend. Each user registers their own OAuth app at their provider and pastes the Client-ID into Settings → Erweiterungen → Verbindungen → Konfigurieren. The Connections screen shows "Konfigurieren" instead of "Verbinden" until a Client-ID is set, with an inline explanation. You do NOT need to test the full OAuth flow — the Konfigurieren button reveals the per-provider setup form.

C) MCP servers — accept any HTTPS URL.
   Settings → Erweiterungen → MCP-Server → "+" → enter any HTTPS URL and tap Speichern. The connection state shows in the row.

DATA COLLECTION: None. Lokalo runs no servers, has no analytics SDK, and does not phone home. The only network requests Lokalo makes are:
- HuggingFace downloads of GGUF model files (initiated by the user)
- HuggingFace download of an embedding model file (only if user enables RAG)
- Direct API calls to GitHub / Google / Microsoft (only if user signs into one of those connectors)

All connector tokens live exclusively in the iOS Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly), never in iCloud, never on a Lokalo server.
```

## App Store Connect — Schritt für Schritt

1. App Store Connect → My Apps → "+" → New App
2. Platform: iOS, Name: **Lokalo**, Primary Language: German, Bundle ID: `com.slavkoklincov.lokal`, SKU: `lokalo-1`
3. Pricing: Free
4. App Privacy → Data Collection → "We do not collect data from this app"
5. App Information → Subtitle / Categories aus diesem Dokument
6. Version 1.0 → Description, Keywords, Support URL, Privacy URL, Promotional Text, Screenshots aus `screenshots/appstore/`
7. Build → wenn er hochgeladen ist, hier auswählen
8. App Review Information → Notes aus dem Block oben einfügen, Demo-Account: nicht nötig (kein Login bei Lokalo)
9. Save → Submit for Review (oder erstmal nur TestFlight)

---

## Vor dem Production-Launch — offene Entscheidungen

These items are NOT blocking for TestFlight. They MUST be addressed before submitting v1.0 to the App Store production track. Once a build is reviewed and published, several of them become irreversible.

### 1. Bundle Identifier rename: `com.slavkoklincov.lokal` → `com.slavkoklincov.lokalo` (or `it.klincov.lokalo`)

**Why:** The current bundle ID drops the trailing "o" from the app's actual name "Lokalo". Looks like a typo, inconsistent with the brand. **Pre-launch is the only safe time to fix this** — once submitted to the App Store production track with reviews/ratings, the bundle ID is locked to that App Store Connect entry forever and cannot be migrated.

**Decision needed before the rename:**
- Final bundle ID string: `com.slavkoklincov.lokalo` vs. `it.klincov.lokalo` (reverse-DNS of the owned domain `klincov.it`, more professional but bigger break)
- Whether to also rename the Keychain services in `OAuthTokenVault` and `MCPStore` (clean, but invalidates existing TestFlight users' OAuth + MCP tokens — they have to re-login)
- Whether the current App Store Connect entry under `com.slavkoklincov.lokal` already exists. If yes, decide whether to delete (only possible while no build has been submitted to Apple) or abandon it. The old bundle ID gets "burned" to the developer account either way.

**Scope when ready:** ~20 occurrences across 13 files. The full list, captured at audit time:
- `project.yml` — `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleURLName`, `CFBundleURLSchemes`
- `Lokal/Info.plist` — auto-regenerated by xcodegen from `project.yml`
- `Lokal.xcodeproj/project.pbxproj` — auto-regenerated by xcodegen
- `Lokal/OAuth/OneDriveOAuth.swift` — `redirectURI` + `callbackScheme` constants
- `Lokal/OAuth/OAuthTokenVault.swift` — `Keychain(service:)` (decide based on point 2 above)
- `Lokal/State/MCPStore.swift` — `Keychain(service:)` (same)
- `Lokal/Engine/FileLog.swift` — `Logger(subsystem:)` + the doc comment at the top
- `Lokal/Features/Settings/ConnectionsSettingsView.swift` — three user-facing instruction strings (GitHub callback, Google bundle ID, Microsoft redirect URI)
- `README.md`, `CLAUDE.md`, `AppStoreMetadata.md` — bundle ID references in docs

**Side effects to plan for:**
- Register new App ID at developer.apple.com → Identifiers (and re-add the Increased Memory Limit capability if you've enabled it on the old one — see point 2 below)
- Re-create OAuth client IDs at all 3 providers — Google's iOS Client ID is **bundle-specific** so the existing one stops working entirely
- New TestFlight group, re-invite all testers, re-upload all builds
- Old App Store Connect entry (if any builds were submitted) becomes a permanently abandoned tombstone

### 2. Increased Memory Limit entitlement (`com.apple.developer.kernel.increased-memory-limit`)

`project.yml:74-82` has the entitlement block commented out. Without it, the larger models (Phi-4 Mini ~2.5 GB, Gemma 3 4B ~2.5 GB, SmolLM3 3B ~2 GB) will be Jetsam-killed mid-stream on iPhones with <8 GB RAM.

**Action:** App Store Connect → Identifiers → `<bundle-id>` → Capabilities → enable "Increased Memory Limit". Apple grants this automatically for first-party AI/LLM apps — no review beyond the checkbox. Then uncomment the entitlement block in `project.yml` and re-run `xcodegen generate`.

If you do the bundle ID rename in point 1 above, this capability MUST be enabled on the new App ID, not the old one.

### 3. Privacy / Support / Marketing URLs must return real HTML

Apple verifies the URLs listed in App Store Connect during review. The following must be live and branded before submission:

- `https://klincov.it/lokal` — marketing landing page
- `https://klincov.it/lokal/support` — support contact, FAQ
- `https://klincov.it/lokal/privacy` — privacy policy specifically mentioning HuggingFace downloads, Keychain token storage for OAuth connectors, and an EU Impressum (Wien-based developer)

A 404 or placeholder page on any of these URLs is an automatic reject under Guideline 5.1.1.

### 4. App Privacy nutrition label questionnaire

App Store Connect → App Privacy → Data Collection → click through the questionnaire. Answer: **"We do not collect data from this app"**. This is honest as of the Phase H copy rewrite — Lokalo runs no servers and the optional cloud connectors flow directly between the user's iPhone and the provider, never through Lokalo.

### 5. Llama Community License attribution check

`LicensesView.swift` already shows "Built with Llama" attribution which satisfies the Llama 3.x Community License's display requirement. Verify before submission that the attribution is still visible in the shipped build (Settings → Lizenzen) — if a future commit changes that screen, the attribution requirement breaks silently.
