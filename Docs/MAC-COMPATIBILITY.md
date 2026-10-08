# Bound on Apple silicon Mac

Bound uses Delta’s existing **iPad app running on Apple silicon Mac** route. In Xcode, open `Bound.xcodeproj`, select `Bound`, and choose **My Mac (Designed for iPad)**. This is the same iOS application and pinned Delta emulator backend. It is not a native AppKit/macOS or Mac Catalyst target, and Intel Macs are not supported by this route.

## Desktop companion controls

On Mac, gameplay includes a persistent toolbar with Menu, Friends, Notes, Types and PiP options. It remains usable when a keyboard or gamepad hides the virtual controller. Menu opens Delta’s existing pause menu for save/load, library, Friends and Bound settings.

- Command–1/2/3 select Friends/Notes/Types and restore a hidden companion.
- Command–Shift–P hides or restores a floating companion.
- The PiP menu selects a corner, size and opacity without touch emulation. Each panel retains its own settings; Types remains opaque.
- Bound portrait retains stacked screens; wide windows use the existing landscape game and floating companion. Classic layout retains Delta’s geometry.
- Notes remain local per game. Editing pauses gameplay; Done resumes through the existing eligibility checks.
- Closing/backgrounding the gameplay scene stops sharing. Returning does not automatically join a friend again.

Command shortcuts are excluded from Delta’s modern Mac keyboard input stream, including custom game mappings. Held ordinary keys are released when Command is pressed to avoid a swallowed release leaving an emulated button down. iPhone/iPad keyboard behavior is unchanged.

## Dependencies and unchanged data paths

No new SDK, service, emulator, target or entitlement is introduced. The existing iOS Agora 4.6.4 and OperatorKit binaries remain appropriate to the iOS compatibility route; they are not represented as native macOS libraries. Library import, Delta battery saves/save states, controller mapping, Metal-on-Mac rendering, the account backend and friend video pipeline remain shared with iOS. Friend capture currently covers bitmap-backed cores at 240×160; GPU-core sharing is outside the existing implementation.

The upstream revisions are preserved. `PrototypePatches/deltacore-mac-command-shortcuts.patch` records the small keyboard adaptation on top of the committed snapshot, and the source-integrity manifest records its hash.

## Verification

Validated with Xcode 27 using isolated build output and the committed dependency pins:

- 49 portable model tests pass, including resized-window boundaries and toolbar/PiP clearance.
- Source integrity verifies all 16,879 pinned files against the updated compatibility manifest; the keyboard patch reverses cleanly.
- Unsigned Release builds pass for both **My Mac (Designed for iPad)** and generic iPhone destinations.

The focused UIKit/core test bundle compiles and links for the Mac compatibility destination, including the new desktop toolbar, panel preference and keyboard regression tests. **The hosted tests did not execute:** macOS rejected the unsigned QA host with `0xe800801c` (no code signature), the iOS SDK disallowed local ad-hoc signing, and the existing Apple provisioning profile did not include this Mac VM. No device registration, provisioning update or security-setting change was made.

The exact test destination selector is `platform=macOS,arch=arm64,variant=Designed for iPad`; omitting the variant can select Catalyst for the test scheme. Validation used an isolated `com.evanvonessen.bound.macqa.Bound` identity and original generated test cartridges. Logs and result bundles remain in the ignored `.build/mac-validation/` directory. No live account/friend was contacted by the offline checks.

Build, model and Mac runtime results are separate evidence: successful compilation does not establish runtime behavior. On a Mac covered by the existing development team’s provisioning profile, run the hosted tests and verify ROM import/save/load, keyboard/gamepad input, Notes editing, type-chart navigation, PiP menus, window resizing/fullscreen, audio and scene lifecycle. Real friend sharing and App Store availability also require separate validation. Public distribution remains subject to the repository’s existing licensing and release gates.
