# Bound TestFlight preparation

Review date: 2026-10-06. **Local archive preparation is not TestFlight or distribution approval.** Upload, app-record creation, signing-account changes, agreements, and tester distribution remain on hold.

## Identity

| Setting | Current value |
| --- | --- |
| iPhone display label | Bound (explicitly authorized change from Bound 2) |
| Project / scheme / product | Bound.xcodeproj / Bound / Bound.app |
| Internal target / module | Delta (preserved for upstream compatibility) |
| Bundle ID | com.evanvonessen.bound.deltaprototype |
| Existing team | 3N83BX5M9G |
| Version / build | 0.5.5 / 172 |
| Deployment target | iOS 17.0; iPhone and iPad |

No bundle ID, team, project name, version, capabilities, or dependency pins were changed. The display label does not select an App Store name or reserve one. Before an upload, inspect the existing App Store Connect record and uploaded build numbers. Decide whether the current bundle ID is the permanent release identity; changing it creates a different app identity and does not automatically migrate existing local app data. Do not substitute the older `com.evanvonessen.bound` identity merely because a development profile exists for it.

## Local preparation and verification

The ordinary Bound scheme archives its native app in Release. The local archive uses Xcode 27.0 (27A266a), iOS 27.0 SDK, arm64, and the existing Apple Development identity. Existing Apple Development and Apple Distribution certificates were inspected read-only. Only development provisioning profiles are cached; no matching App Store distribution profile was found. No provisioning updates or new signing assets were requested.

The final local archive succeeded and contains one application product. Deep/strict app signature verification and individual checks for all 19 embedded frameworks passed. Its effective entitlements match the existing bundle ID and team; `get-task-allow` is true, and its device-provisioned profile has no beta-reports entitlement. This confirms development signing, not TestFlight distribution signing. The profile expires 2027-09-30. The bundled app privacy manifest matches the committed source, and the checked Debug fixture launch arguments are absent from the Release executable. Local evidence is under ignored `.build/testflight-readiness/` (`archive-final.log`, `archive-audit.json`, `models.log`, and `source-integrity.log`).

The original Bound icon is 1024 × 1024 without an alpha channel and is referenced by the Icon Composer asset. The compiled app includes its primary icon metadata. The selected app entitlements source is the empty `Delta/Delta.entitlements`. The pre-existing non-exempt-encryption flag is false; it was not changed or treated as a completed export-compliance review.

The app now bundles `Delta/Supporting Files/PrivacyInfo.xcprivacy` for verified app-owned required-reason API uses:

| Category | Reasons | Source evidence |
| --- | --- | --- |
| User defaults | CA92.1 | Local appearance, panel, controller, and account logout preferences |
| System boot time | 35F9.1 | Frame throttling and elapsed-time scheduling in BoundDeltaFrameTap and FriendSharingSession; sharing timestamps use a stream-relative epoch |
| File metadata | C617.1, 3B52.1 | Local files and user-selected BIOS import size validation in MelonDSCoreSettingsViewController |

This manifest intentionally makes no unverified data-collection declarations. It is not a substitute for SDK manifests, the backend/SDK data-flow review, or App Store privacy answers. All 47 model tests and the 16,879-file pinned-source integrity check passed. No personal ROMs or live accounts were used. This metadata preparation does not add new physical-device or live-network validation.

## Remaining blockers

1. **Distribution rights:** The recorded Agora proprietary binary SDK versus Delta AGPL compatibility question remains unresolved. Standalone core/framework permission provenance, OperatorKit, and the supplied type-chart artwork also remain open in [the dependency inventory](LICENSES/DEPENDENCY-INVENTORY.md). Agora remains unchanged. Do not distribute this archive until the required permissions are resolved.
2. **SDK privacy coverage:** The linked app contains Alamofire 4.7.3, GoogleSignIn 6.2.4, GTMAppAuth 1.3.1, GTMSessionFetcher 2.3.0, and SDWebImage 3.8.3 without corresponding bundled privacy manifests. All five appear on Apple's required-SDK list. The archive does include manifests for AppAuth, RevenueCat, ZIPFoundation, and AgoraRtcKit. Review the required-reason API usage of each embedded core/framework too. Preserve the pinned sources until a reviewed dependency update or accurately supported manifest integration is authorized; do not invent SDK declarations.
3. **Apple account state and provisioning:** An App Store Connect record, membership/agreements state, app access, and previous uploaded build numbers have not been verified. This execution session exposes no App Store Connect connector, browser-control tool, plugin discovery action, or configured `asc` CLI. A development-signed archive is not an App Store distribution package. Confirm the intended existing record and permanent bundle ID before obtaining a matching distribution profile or creating a record.
4. **Submission information:** Review the privacy policy and disclosures for account identity, friend relationships, gameplay video, backend retention, and SDK diagnostics. Confirm export-compliance answers, applicable age-rating responses, beta description, feedback/review contact, and reviewer access using authorized test data. Internal versus external tester scope and any submission must be explicitly approved. External testing may require beta review.

The binary import audit also found missing per-framework manifest coverage for file-metadata APIs in Agoraffmpeg and GBADeltaCore; boot-time APIs in DeltaCore; file-metadata/defaults APIs in MelonDSDeltaCore; file-metadata/boot-time APIs in N64DeltaCore and aosl; and defaults APIs in OperatorKit. Imports identify review targets; correct reasons still require source or vendor evidence. No vendor declarations were fabricated and no pinned framework was modified.

## Local archive command

From the repository root, with existing authorized signing assets:

```sh
xcodebuild -project Bound.xcodeproj -scheme Bound -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath .build/testflight-readiness/Bound.xcarchive \
  CLANG_ENABLE_EXPLICIT_MODULES=NO SWIFT_ENABLE_EXPLICIT_MODULES=NO archive
```

This command only archives locally. Do not add `-allowProvisioningUpdates`, export/upload commands, or account credentials as part of this preparation. Local logs, archives, and signing material are ignored by Git and must remain out of commits.

## Apple references checked

- [Current upload requirements](https://developer.apple.com/news/upcoming-requirements/): Xcode 26 or later with the iOS 26 SDK or later; iOS deployment target 13 or later. The local toolchain and deployment target exceed those minimums; server-side validation was not performed.
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/): build association uses the bundle ID and version, and builds must be processed by Apple before testing.
- [Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/): listed SDKs require manifests, with signatures additionally required for relevant binary dependencies.
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons): declarations must match actual usage; an app manifest does not cover a dynamic SDK's own API use.
- [TestFlight](https://developer.apple.com/testflight/) and [creating an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/): account setup, test information, and any review are separate from a successful local archive.
