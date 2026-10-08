# Bound account milestone — deployment pending

The app now offers **Friends → Create Account** with Email and Password only.
Friend display names remain independent, per connection. Signup calls existing
Supabase Auth, handles both email-confirmation and immediate-session responses,
and makes no profile/schema changes. Passwords are never saved or logged.
Confirmation links use the existing Auth Site URL: no new callback is assumed.
The user confirms email, then returns to Friends → Sign in.

Signed-in Friends includes a red **DELETE MY ACCOUNT** action. The app fetches
the current Auth user, requires the typed account email to match (ASCII,
case-insensitive, trimming surrounding space/tab/CR/LF), and sends an authenticated
request. The server independently verifies identity and email. Typing an email is
intent confirmation; it never chooses the user to delete. Existing authentication
and confirmed-email gates are retained. No extra password prompt is required by
this existing session-authenticated server contract.

Deletion blocks cloud writes, removes owned Supabase storage through the Storage
API, purges Bound cloud rows and friend connections, deletes the Auth user, then
records completion. A 256-bit capability is saved separately in device-only
Keychain before beginning; after a lost response or revoked session, **Retry
account deletion** checks/resumes that same job. Success requires a complete
receipt. Local games/notes and separate Google Drive/Dropbox data are untouched.
The minimal permanent deletion marker/capability digest remains to prevent stale
JWT writes and safely resolve retries. It contains no password, email or content.

## Exact proposed live changes — approval required

Project: `qevnxhngdtlyihhmvnjv`. No live change has been made.

1. Inspect/diff the current `public.cup117_delete_account(text,jsonb)` against the
   snapshot in `proposed-contract.sql`. Apply that SQL in one transaction: add the
   current Auth email check for email intents; retain legacy username intents,
   locking, write fences, cleanup and capability binding. Explicitly restrict
   execution to `service_role`. No new table, profile or Auth setting is needed.
2. Deploy existing Edge Function **delete-account** with `index.ts` and
   `handler.mjs`, `verify_jwt=false`. The handler performs Auth getUser validation
   for begin; resumes use the existing preauthorized capability. Keep the existing
   server-only `SUPABASE_SERVICE_ROLE_KEY` and
   `CUPCAKE_SUPABASE_PUBLISHABLE_KEY` configuration; never put the service key in
   the app. Do not create credentials or change unrelated functions.
3. Verify live contract with a separately approved disposable QA account, including
   email mismatch, revoked session, storage cleanup and lost-response resume.
   No live accounts were created or deleted in current QA.
4. Upload a **new app build** only after separately authorized. Reviewed **1.0 (4)**
   does not contain this new UI. Until deployment, its old username-only endpoint
   rejects new email intents before beginning; the app reports failure truthfully.

## Verification

- `swift test --package-path PrototypeTests`: synthetic lifecycle, persistence,
  cancellation, duplicate submissions, errors, email intent and capability retry.
- `node --test Backend/account-deletion/handler.test.mjs`: injected fetch only.
- Isolated PostgreSQL 17: apply `fixture.sql`, `proposed-contract.sql`, then
  `contract.test.sql` with ON_ERROR_STOP. **fixture.sql is local only**, never live.
- Release iPhone/iPad build per repository instructions; logs in ignored
  `.build/account-validation`. Hosted/device UI and live Auth delivery still need
  release QA. Existing App Store legal, UGC and recording gates remain separate.

## Draft-only App Review facts

After deployment and a replacement build, reviewer steps will be:
**Open a game → Menu → Friends → Create Account → Email and Password**;
confirm email if requested, then sign in. Account deletion is in signed-in
**Friends → DELETE MY ACCOUNT**, confirmed by typing that account's email.
Do not state these steps exist in reviewed build 1.0 (4), or that deletion is live,
until the replacement build and server deployment are confirmed. The user submits
the review reply; this work posts nothing to App Store Connect.
