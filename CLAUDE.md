# Lokalo

Native iOS app that runs local LLMs on iPhone via llama.cpp + Apple Metal.
GGUF model download from HuggingFace, on-device chat, RAG (USearch +
embeddings), MCP tool calling, OAuth connectors (GitHub / Google Drive /
OneDrive). Bundle: `com.slavkoklincov.lokal`. Team: `SMPDFBGL64`.

## Build

```bash
# 1. Fetch the llama.cpp XCFramework (one-time, ~250 MB, gitignored)
./scripts/fetch-llama-framework.sh

# 2. Generate the Xcode project from project.yml
xcodegen generate

# 3. Open in Xcode (or build from CLI)
open Lokal.xcodeproj
```

CLI build for the simulator:

```bash
xcodebuild -project Lokal.xcodeproj -scheme Lokal \
  -destination "platform=iOS Simulator,id=AE352555-D75A-4906-8299-0A12E22FE56E" \
  -configuration Debug build
```

CLI test:

```bash
xcodebuild -project Lokal.xcodeproj -scheme Lokal \
  -destination "platform=iOS Simulator,id=AE352555-D75A-4906-8299-0A12E22FE56E" \
  test
```

## Bumping the build number

For every TestFlight upload Apple requires a unique build number. Either
let `upload-to-testflight.sh --bump` do it, or edit `project.yml` manually
and bump **both** keys (they must match):

```yaml
CFBundleVersion: "3"            # under targets.Lokal.info.properties
CURRENT_PROJECT_VERSION: "3"    # under targets.Lokal.settings.base
```

Then `xcodegen generate` to regenerate the .xcodeproj.

## Shipping to TestFlight

The recommended path is the wrapper script, which authenticates via an
**App Store Connect API key (.p8)** instead of an Xcode-cached account.
This bypasses the recurring `xcodebuild` "Failed to Use Accounts" bug.

```bash
./scripts/upload-to-testflight.sh           # current build number
./scripts/upload-to-testflight.sh --bump    # auto-increment first
```

### One-time setup of the API key

The `.p8` lives **outside the repo** and is never committed. On this
machine the key is at `/Users/slavkoklincov/Code/Build_AppStore/AuthKey_*.p8`.

1. App Store Connect → Users and Access → Integrations → App Store Connect API
2. Generate a key with **App Manager** role (or higher)
3. Download the .p8 file once (Apple does not let you re-download it)
4. Copy the template and fill in the three values:
   ```bash
   cp scripts/testflight-config.sh.template scripts/testflight-config.sh
   $EDITOR scripts/testflight-config.sh
   ```
   `scripts/testflight-config.sh` is gitignored.

### What the upload script does

1. Sources `scripts/testflight-config.sh` (pre-flight sanity check on
   the .p8 path — see note below)
2. Optionally bumps `CFBundleVersion` if `--bump` is passed
3. Runs `xcodegen generate`
4. `xcodebuild archive` (Release / generic iOS)
5. `xcodebuild -exportArchive -allowProvisioningUpdates
   -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`
   — authenticates via the `.p8` App Store Connect API key, bypassing
   Xcode's cached Apple ID credentials in the macOS login keychain
   entirely. This avoids the recurring "Failed to Use Accounts /
   missing Xcode-Username" bug where Xcode loses its cached credentials
   roughly every other run. An earlier version (commit `cb8c1d0`) had
   switched to Xcode Apple ID auth because the `.p8` was tripping a
   "Cloud Managed Distribution Certificates" scope block — that
   restriction was lifted on Apple's side and the `.p8` path now works
   end-to-end. Verified on 2026-04-11 with Build 9 (commit `dd199b7`).

### Prerequisites (one-time setup on this machine)

1. **Apple Distribution cert in login keychain.** Create it via
   Xcode → Settings → Accounts → Team → Manage Certificates → `+` →
   "Apple Distribution". Without it, `security find-identity -v -p
   codesigning` only lists the Apple Development cert and export fails.
2. **Keychain partition list includes `apple-tool:` and `apple:`.**
   Set once via:
   ```zsh
   read -s "KC_PASS?Login-Passwort: " && echo && \
     security set-key-partition-list -S apple-tool:,apple: \
     -s -k "$KC_PASS" ~/Library/Keychains/login.keychain-db && \
     unset KC_PASS
   ```
   Without this, codesign prompts a dialog every call or fails with
   `errSecInternalComponent`. "Allow all applications" in Keychain
   Access GUI is NOT sufficient — it sets the ACL but not the
   partition list.

### Fallback (manual upload)

If the script ever fails, the archive is at `build/Lokal.xcarchive`. Open
Xcode → Window → Organizer → Archives → "Distribute App" → "App Store
Connect" → "Upload" → Automatic signing. This should only be needed if
one of the prerequisites above is missing on a fresh machine.

## Project layout

- `Lokal/` — main app (SwiftUI)
- `Lokal/App/LokalApp.swift` — store graph constructed in `init()` (no `attach()`)
- `Lokal/Engine/` — llama.cpp wrapper (LlamaEngine, sampling, file logging)
- `Lokal/State/` — observable stores (ModelStore, DownloadManager, ChatStore, …)
- `Lokal/Features/` — SwiftUI screens grouped by feature
- `Lokal/RAG/` — USearch + chunk store + embedding pipeline
- `Lokal/OAuth/` — GitHub / Google Drive / OneDrive PKCE flows
- `Lokal/Models/LokaloError.swift` — German-language error wrapper
- `Frameworks/llama.xcframework/` — gitignored, fetched on demand
- `LokalTests/` — unit tests
- `LokalUITests/` — UI tests
- `scripts/` — build & upload helpers
- `onboarding-preview/` — standalone HTML mockups for the onboarding beats

## Conventions

- All UI strings are German. Wrap errors via `Error.lokaloMessage` from
  `Lokal/Models/LokaloError.swift` — never expose `error.localizedDescription`
  directly to the user
- Stores are constructor-injected as `let` dependencies in `LokalApp.init()`,
  in dependency order. The old `attach()` pattern is gone — adding a store
  means extending the constructor, not chasing weak references
- The `preferredFirstModelID` from onboarding routes the user directly to
  `ModelDetailView` (via `RootView.task`), not to an empty library
- RAG `IndexingService` caches per-source `(VectorStore, ChunkStore)` pairs;
  invalidate via `invalidateCache(for:)` whenever a source is removed/reindexed
