# Bound completion checkpoint — 2026-10-08

Published to `evanvonessen/bound` **main** without force:

- [1fb5a55c — Add friend safety controls and simplify Bound settings](https://github.com/evanvonessen/bound/commit/1fb5a55c6be6d87ad0b6913857bd6caf8b1ed886)
- [50ba1ef3 — Publish community rules and prepare App Review instructions](https://github.com/evanvonessen/bound/commit/50ba1ef3afc8f71f89b84f66502411cd9291b1fd)

The existing `92229c54` account-creation commit was already on main when work
resumed. Separate macOS work at `4a3db003` was not merged. All prior worktree
edits were preserved. Upstream module/core names, dependency pins and patches
remain intact. No credentials, signing material, app data or build output was
committed.

## Completed source and public site

- Email/password-only signup and confirmation-email state, authenticated email
  deletion UI/retry/cancel, and no client service credential retained.
- Client Report/Block/Unblock, bounded private report schema, authenticated friend
  enforcement, text filtering, token gate changes, operator SQL review workflow,
  rollback snapshots, and honest already-issued-token limitations prepared.
- Requested settings hidden reversibly; opacity slider and GBA core settings
  visible; Bound arrangement/Classic appearance enforced without overwriting
  saved choices. Other supported systems still use their existing cores.
- About Bound cleanup and grouped backend details, with actual bundled software
  license access retained. See `HIDDEN-FEATURES.md` for exact restoration scope.
- [Community rules](https://evanvonessen.github.io/bound/moderation.html) published,
  linked minimally from Friends/support/privacy and verified in the live browser.
  [GitHub Pages deployment](https://github.com/evanvonessen/bound/actions/runs/37746740422)
  completed successfully at `50ba1ef3`.
- [App Review setup and reply draft](APP-REVIEW-SETUP.md) prepared only. Build
  **1.0 (4)** remains the reviewed build; changes need a new uploaded build.
- [Tobu Tobu Girl Deluxe demo rights and attribution](DEMO-ROM.md) verified from
  creator sources. ROM plus original MIT/CC BY terms and credits are on this
  VM Desktop, outside the repository/app bundle. SHA-256 matches the documented
  262144-byte official ROM. No downloaded program was run.

## Passed checks

- **59** Swift model tests, including retained hidden-preference restoration.
- **13** server handler tests using injected fetch, covering self-only deletion,
  rejection paths and moderation token gates.
- **9** focused offline iOS Simulator integration tests: account persistence,
  Report/Block/Unblock state and actual bundled source/license notices.
- Both isolated **PostgreSQL 17** account-deletion and moderation contracts,
  using local fixtures and ON_ERROR_STOP. No tests were run against real accounts.
- Final **unsigned Release iPhone build** through Bound.xcodeproj / Bound,
  arm64, existing dependency pins, automatic package resolution disabled.
  Existing dependency/module warnings remain; build succeeded.
- All four site pages' local links/assets/anchors. Policy layout inspected at
  actual 1888, 559 and 380 CSS-pixel widths, with no horizontal overflow.

Ignored logs: `.build/account-validation/final-models.log`, `final-server.log`,
`final-integration.log`, `final-moderation-sql.log`, `final-deletion-sql.log`,
`final-release.log`. The focused simulator result bundle is under
`IntegrationDerivedData/Logs/Test` in the same ignored directory.

## Remaining blockers and limits

1. **Live backend deployment did not apply.** The exact bundle was approved by
   the user, then its one migration invocation was interrupted after repeated
   confirmation prompts. No completion or operation ID was returned. Read-only
   verification found no new migration/schema and unchanged database fingerprints;
   `delete-account` remains **v2**, `agora-token` **v3**. Supabase inherits
   **Allow read actions**, so writes prompt; repeated prompts within this one
   invocation remain unexplained. No retry, permission change or alternate
   mutation route was used. See `Backend/moderation/README.md` for evidence and
   the bounded recovery path. New email intents/report/block are not live yet.
   Read-only Safari inspection confirms dashboard and existing function editor
   access without an access-denied message; it does not resolve connector write
   confirmation. The overview reports **Unhealthy**, whose cause is unverified.
   A guarded user-run SQL handoff and exact two-function update/verification
   sequence are in the moderation README. No browser deployment was performed.
2. **New icon and four artwork files: HTTP 403.** All five new Library references
   were tried through supported VM materialization and stopped at denial.
   No supplied pixels could be inspected or added to GitHub. Existing icon and
   artwork remain unchanged. VM-local copies are still needed through an
   authorized working transfer. Do not bypass the denied references.
3. **No physical-device/latest-public-OS recording or live paired sharing QA.**
   Simulator checks do not prove email delivery, authenticated deployed report
   enforcement, successful deletion, network latency or universal immediate
   RTC disconnect. No real accounts were deleted and no real abuse reports sent.
4. **No App Store upload/submission or reply was sent.** New-build upload, actual
   reviewer credentials and physical recording remain user steps. No demo account
   or password was invented. Free/same functionality across offered regions
   reflects the user's confirmation, not an App Store Connect change.
5. **Distribution licensing review remains unresolved:** Agora/AGPL,
   OperatorKit and Pokémon artwork. No full-compliance attestation is made.

The read-only security advisor also reports existing authenticated SECURITY
DEFINER RPCs and private RLS tables without policies, plus disabled leaked-password
protection. No unrelated access/Auth settings were changed. References:
[RPC advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[private RLS advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
