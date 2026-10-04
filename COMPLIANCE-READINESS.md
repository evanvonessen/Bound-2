# Bound 2 source and distribution readiness

This document records work still needed for a release; it is not legal certification, a license grant or a source offer. The user made https://github.com/evanvonessen/bound public; read-only verification confirmed that status on 2026-10-04. This work does not change repository visibility. Root COPYING and original dependency notices are preserved. Read LICENSES/DEPENDENCY-INVENTORY.md for the exact versions/files inspected, and LICENSES/BOUND2-MODIFICATIONS.md for the modification notice.

## Build the current tracked source

Developers can clone the public source repository and open Bound.xcodeproj. For a matching released binary, first check out its recorded release commit rather than assuming the latest main branch has identical inputs. Choose the Bound scheme, select an iOS 17+ device and an existing signing team, then Run. Run uses Release. The native app's internal module/target remains Delta; there is one app foundation and no nested build wrapper.

Tracked snapshots include native core/framework sources, controller assets, generated model files and CocoaPods build inputs. No preparation command, Homebrew, Git LFS, submodule initialization, pod install or mogenerator installation is required for ordinary Run. Xcode resolves the versions/revisions recorded in Bound.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; those include downloaded binary SDKs whose permission/source status is separately unresolved. Mogenerator is optional only for developers deliberately regenerating model sources.

Existing source-integrity verification: `python3 PrototypeTools/verify_sources.py`. Model tests: `swift test --package-path PrototypeTests`. Aggregate hosted/Simulator/unsigned Release checks: `PrototypeTools/verify.sh`, using a dedicated QA_SIMULATOR_ID. These are developer checks, not legal or physical-device certifications. README.md contains the actual normal build/import workflow. Do not create signing credentials/profiles or include them in source packages.

## Prepare exact corresponding-source delivery

Before distributing a binary, identify the exact release commit, version/build, artifact SHA-256, dependency pins and modified snapshot hashes. Preserve actual build scripts/project files, generated inputs needed to build, patches and applicable third-party notices. Verify a clean checkout builds with the documented prerequisites and that a recipient can actually obtain the matching materials. Keep credentials, signing keys/profiles, account sessions, personal ROMs and app data out of source packages.

The public repository provides access to tracked build sources and inputs, but source/binary version matching still needs verification for each release. The working tree under review is intended for 0.5.5 (172); do not claim it matches a released artifact until the exact commit is published and linked with that artifact's digest. Record that mapping in the release notes and artifact metadata. Recipients can then clone the repository and check out the recorded commit:

```sh
git clone https://github.com/evanvonessen/bound.git
cd Bound-2
git checkout <exact-commit-recorded-with-the-downloaded-release>
open Bound.xcodeproj
```

The angle-bracket value above is an instruction to use the actual published commit, not an existing tag or a claim that source delivery is complete. The root license and governing component licenses determine what a final arrangement must include. Missing SDK source/permissions and additional licensing restrictions must be resolved, not hidden by an acknowledgement page. Public source availability alone does not establish proprietary SDK permission or legal compatibility.

## Concrete publication gates

1. Establish the permission provenance of the exact DeltaCore/core wrappers, Harmony/Roxas/AltKit and relevant third-party database/artwork content. Missing standalone license files are not treated as permissive grants or as proof of illegality.
2. Assess the exact engine and component terms together: root AGPLv3, VBA-M GPLv2-or-later with per-file/APU/zlib exceptions, other GPL/LGPL components, and the pinned Snes9x/Genesis Plus GX non-commercial restrictions. This document makes no compatibility conclusion and does not relicense dependencies.
3. Identify the governing Agora 4.6.4 / AgoraInfra 1.3.5 binary SDK agreement and rights for the active binary frameworks, including any third-party codec notices. The Swift package wrapper's MIT file is not assumed to cover those SDK binaries. Resolve compatibility with the intended distribution model without accepting new terms here.
4. Establish OperatorKit 1.0 (1) binary permission/source provenance and applicable conditions. DeltaOperator wrapper source is not a substitute for the embedded binary's rights.
5. Establish the supplied type-chart and reused artwork/font/branding permissions. Preserve original notices and avoid implying affiliation.
6. Package and verify complete matching notices, accurate dated modification notices and usable recipient source access for the exact released build. Keep upstream component names/attributions; do not claim notices alone complete compliance.
7. Complete actual-device gameplay, touch/haptic, audio, rotation/background and live paired Internet-sharing tests. Local raw-RGBA paired fixtures do not verify Agora's codec/network path. Record privacy/data behavior from real code and account/service configuration before writing any store/privacy claims.
8. Review proposed App Store/TestFlight/other distribution requirements against the resolved licenses/SDK agreements and actual build. No submission, public visibility change, agreement acceptance, maintainer outreach or account creation is performed by this readiness work.

Functional testing and a successful signed build are useful engineering evidence; they are not public-release clearance. The remaining SDK/dependency decisions require evidence and, where needed, qualified review before distribution claims change.
