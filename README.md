# Bound 2

A private Delta-based Bound app with friend video, notes and a type chart. This repository contains one app foundation; the original Bound/mGBA checkout is untouched.

## Run on an iPhone

Prerequisites: Xcode (validated with Xcode 27), iOS 17+, Homebrew and the official source tools:

```sh
brew install mogenerator git-lfs
git clone https://github.com/evanvonessen/Bound-2.git
cd Bound-2
bash PrototypeTools/prepare.sh
open Bound.xcodeproj
```

Select **Bound**, select your iPhone, choose your existing signing team if needed, then Run. Run uses Release. The native app target is internally named Delta to retain upstream module and vendored CocoaPods identities; this is a direct app build, not a nested app-build wrapper. Version 0.5.0 (167), display name Bound 2. The separate prototype bundle identity is retained so updates preserve its local data.

Import a supported ROM through the Library **+** button. The Files picker accepts regular data when providers use alternate types; the importer validates supported file extensions and registered cores. Unsupported files show an import error. Gameplay settings offer Delta Default/Bound layouts, themes, native haptics and button placement. The floating toolbar selects Friends, Notes or Types.

Friends uses the existing Bound backend and Agora adapter. No new account or service is provisioned. Physical gameplay and real Internet friend-sharing still require device validation; local automated tests use original generated cartridges and offline transport.

## Build and verification

`PrototypeTools/prepare.sh` downloads pinned public dependency sources, applies committed compatibility patches and prepares public client configuration. Modified dependency worktrees are expected; the patches are versioned here. Do not discard them. CocoaPods sources are vendored; `pod install` is not required. The existing Podfile and internal Delta target stay aligned. `Systems/build.sh` builds upstream dependency frameworks only. Recorded native-build patches align older dependency deployment targets with iOS 17 and let the app sign embedded GPGX/MelonDS frameworks with its own identity.

`swift test --package-path PrototypeTests` runs model tests. `PrototypeTools/verify.sh` runs models, hosted offline integration, Simulator UI and unsigned iPhone Release validation. Set `QA_SIMULATOR_ID` for an isolated Simulator. Build output and app data are ignored by Git.

## Source and licensing

Upstream Delta and core revisions are pinned in `PrototypeConfiguration/dependency-pins.json` and `BOUND-PROTOTYPE.md`; patches are in `PrototypePatches`. Upstream notices and `COPYING` are retained. This private build has not been cleared for public/App Store distribution: exact dependency permissions and proprietary Agora/OperatorKit compatibility remain release gates. See the upstream README and licenses; no blanket redistribution assurance is made.
