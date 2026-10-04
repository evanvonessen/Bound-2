# Bound 2

A private Delta-based Bound app with friend video, notes and a type chart. This repository contains one app foundation; the original Bound/mGBA checkout is untouched.

## Run on an iPhone

Prerequisites: Xcode (validated with Xcode 27), iOS 17+, and your existing Apple signing team.

```sh
git clone https://github.com/evanvonessen/Bound-2.git
cd Bound-2
open Bound.xcodeproj
```

Core and framework source snapshots are included, including controller assets and generated model files. No preparation command, Homebrew, Git LFS, submodule initialization or mogenerator installation is required for ordinary Run. Xcode resolves the app's pinned Swift packages normally. The optional mogenerator target is only for developers regenerating model sources.

Select **Bound**, select your iPhone, choose your existing signing team if needed, then Run. Run uses Release. The native app target is internally named Delta to retain upstream module and vendored CocoaPods identities; this is a direct app build, not a nested app-build wrapper. Version 0.5.2 (169), display name Bound 2. The separate prototype bundle identity is retained so updates preserve its local data.

Import a supported ROM through the Library **+** button. The Files picker accepts regular data when providers use alternate types; the importer validates supported file extensions and registered cores. Unsupported files show an import error. Gameplay settings offer Delta Default/Bound layouts, themes, native haptics and button placement. The button beside the native Menu cycles Friends, Notes and Types. Friend login and Bound settings are in the native pause menu.

Friends uses the existing Bound backend and Agora adapter. No new account or service is provisioned. Physical gameplay and real Internet friend-sharing still require device validation; local automated tests use original generated cartridges and offline transport.

## Build and verification

Dependencies are tracked source snapshots rather than submodules, so an ordinary clone or pull contains the native build inputs immediately. `PrototypeTools/prepare.sh` is now an optional offline integrity check; it never downloads, overwrites edits or runs during Xcode Build. Source URLs, exact revisions and file hashes are recorded in `PrototypeConfiguration/vendored-sources.json`; compatibility patches remain in `PrototypePatches`. Keep upstream notices when refreshing a dependency and regenerate its manifest hashes after reviewing changes. CocoaPods sources are included; `pod install` is not required. Build-generated GLide revision metadata is kept at its pinned source value in snapshots.

The native app pins official ZIPFoundation 0.9.18; traversal/symlink regression checks cover both extraction and game import. `swift test --package-path PrototypeTests` runs model tests. `PrototypeTools/verify.sh` runs models, hosted offline integration, Simulator UI and unsigned iPhone Release validation. Set `QA_SIMULATOR_ID` for an isolated Simulator. Build output and app data are ignored by Git.

## Source and licensing

Upstream Delta and core revisions are pinned in `PrototypeConfiguration/dependency-pins.json` and `BOUND-PROTOTYPE.md`; patches are in `PrototypePatches`. Upstream notices and `COPYING` are retained. Normal Run uses Release; QA switches and development panels are excluded from that app. This private build has not been cleared for public/App Store distribution: exact dependency permissions and proprietary Agora/OperatorKit compatibility remain release gates. See the upstream README and licenses; no blanket redistribution assurance is made.
