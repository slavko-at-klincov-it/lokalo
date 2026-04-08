# Lokalo

Native iOS app that downloads GGUF language models from HuggingFace and runs
them on-device with llama.cpp. No cloud, no accounts, no telemetry.

* **Bundle ID:** `com.slavkoklincov.lokal`
* **Min iOS:** 17.0
* **Inference engine:** [llama.cpp](https://github.com/ggml-org/llama.cpp) (Apple Metal)
* **UI:** native SwiftUI
* **Curated models:** Llama 3.2 1B/3B · Qwen 2.5 0.5B/1.5B/3B · Phi-3.5 Mini · Phi-4 Mini · Gemma 2 2B · Gemma 3 1B/4B · SmolLM2 1.7B · SmolLM3 3B · TinyLlama 1.1B

## Quickstart

```bash
# 1. Fetch the llama.xcframework binary (~555 MB, not in git)
./scripts/fetch-llama-framework.sh

# 2. Generate the Xcode project from project.yml
xcodegen generate

# 3. Open & build
open Lokal.xcodeproj
```

## Project layout

```
Lokal/                 SwiftUI app source
├── App/               LokalApp.swift entry point
├── Engine/            LlamaEngine actor wrapping llama.cpp
├── Models/            ModelCatalog, ChatTemplate, ModelEntry, Message
├── State/             ModelStore, DownloadManager, ChatStore (@Observable)
└── Features/          Chat, Library, Settings, Onboarding views

LokalTests/            Unit tests (chat templates, catalog, real inference)
LokalUITests/          XCUITest end-to-end UI flow
Frameworks/            llama.xcframework lives here (gitignored, fetched)
onboarding-preview/    Browser prototypes for first-launch animations
scripts/               Helper scripts (fetch-llama-framework.sh)
project.yml            xcodegen project definition
AppStoreMetadata.md    German + English App Store Connect copy
```

## Running tests

```bash
xcodebuild -project Lokal.xcodeproj -scheme Lokal \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

The `InferenceSmokeTests` will run a real Qwen 2.5 0.5B inference if a `.gguf`
file is found in the simulator's `Documents/models` directory.

## Direct device install (no TestFlight)

```bash
xcodebuild -project Lokal.xcodeproj -scheme Lokal \
  -destination "generic/platform=iOS" -configuration Release \
  -derivedDataPath build/dd build \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<TEAM_ID> \
  -allowProvisioningUpdates

DEVICE=$(xcrun devicectl list devices | grep iPhone | awk '{print $4}' | head -1)
xcrun devicectl device install app --device "$DEVICE" \
  build/dd/Build/Products/Release-iphoneos/Lokal.app
```

## License

App code: see LICENSE.
Embedded model weights are downloaded by the user from HuggingFace at runtime
and remain subject to their respective licenses (Llama Community, Apache 2.0,
Gemma Terms, MIT, etc.). See in-app **Settings → Lizenzen** for full attribution.
