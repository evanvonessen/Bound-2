# Bound moderation — prepared deployment

Target: **bound / qevnxhngdtlyihhmvnjv / us-west-1**, verified through the
connected Supabase integration. The separate `coffee` project is out of scope.
At inspection, `delete-account` was version 2, `agora-token` version 3, and no
`bound_moderation_private` schema/functions were present. The user approved the
exact bundle, but the migration call was interrupted without a completion result.
Read-only verification confirms no application; client and isolated-fixture
checks do not prove live operation.

## Deployment recovery

The single migration invocation returned "aborted by user" after 186.2 seconds.
It returned no operation ID, pending-confirmation ID or adapter error explanation.
The user reported repeated confirmation prompts; available tool output does not
establish their cause. No retry or alternate mutation route was attempted.
After interruption, migration history had no new entry, the moderation schema
was absent, existing function versions were unchanged, and database fingerprints
matched the predeployment state: friends `fe5b40ab4ec5fcd844c7bd839093215e`,
deletion `ec8593846751451d1266a621e8fdcc43`. No live data mutation is confirmed.

Keep the existing approval. Resolve the integration confirmation state before
resuming the same bounded deployment through its normal supported route; there
is no callable cancellation tool or returned ID to cancel here. Do not switch
to raw SQL or another route to bypass confirmation. Re-read state before any
future approved retry, and retain the database-fingerprint precondition.
The backend remains pending; do not advertise these controls as live.

## Bounded security deployment

1. Apply `proposed-schema.sql` then `proposed-friend-gates.sql`, and the email
   contract in `../account-deletion/proposed-contract.sql`, as one reviewed
   migration transaction (remove their inner BEGIN/COMMIT when combining).
2. Update only the existing `delete-account` function from that directory and
   `agora-token` from `agora-index.ts` / `agora-handler.mjs`. Both retain
   `verify_jwt=false`: deletion validates Auth identity for begin and uses the
   preauthorized capability for retries; token issuance validates Auth identity
   and caller-authorized friend RPC membership. Existing server environment
   variables are reused. No credentials, admin users, JWT keys, Auth settings,
   signing assets, exposed schemas, or persistent integration access are added.
3. Verify the deployed source/version, RLS and grants, plus safe unauthenticated
   rejection. Do not create a real abuse report or delete a real account in QA.
   Authenticated end-to-end checks require a separately approved disposable
   account and remain pending.

Data effects: five empty private tables hold blocks, report metadata, suspensions,
quotas and review audit. RLS is enabled with no client policies or schema/table
grants for PUBLIC, anon or authenticated. Private helper/review functions have
no client EXECUTE grant. Only `public.cup050_friends(text,jsonb)` is callable by
authenticated users; it checks the current confirmed Auth account, deletion
fence, room membership, blocks/suspensions and rate limits. Account-deletion RPC
execution remains restricted to service_role. The migration itself deletes no
accounts, storage objects, friend rooms, or report rows.

After deployment, a user's own block deactivates that pair's rooms; operator
suspension deactivates that subject's rooms and outstanding invites. Report
metadata is limited to account UUIDs, room UUID, reason category, status/times;
there is no free-text attachment or media upload. Account deletion cascades this
private metadata when the corresponding Auth user is deleted. The existing
permanent deletion fence/capability digest remains, without email or content.
This deployment enables authenticated users to request irreversible self-deletion;
it does not authorize running that action on any real account during QA.

Reports: at most five new reports per 24 hours, one per minute; an identical
report within 24 hours returns its existing ID. Moderation actions share a
60-per-hour quota; own block lists have a 100-entry bound. Existing friend quotas
remain. Limits are serialized in the database, not trusted to the client.

Rollback: retain private report/block/audit tables and history. Reapply
`rollback-friend-gates.sql` and `../account-deletion/rollback-contract.sql` only
after operator review. Restore the saved previous Edge Function sources/versions
through the supported integration. Reverting friend gates disables enforcement,
and reverting deletion rejects new email intents; communicate that before using
rollback. Suspended/blocked inactive rooms are not automatically reactivated.
Deleted accounts or storage cannot be recovered by reverting code. Never drop
moderation tables to roll back an application change.

## Private moderator workflow

Use the operator's **existing authorized Supabase dashboard** → Bound project →
SQL Editor. No new moderator password/account is introduced. Verify the project
reference above before each operation. Reports are allegations, not proof.

Read the bounded queue (no public report API):

```sql
SELECT id, reporter, subject, room, reason, status, created_at, reviewed_at
FROM bound_moderation_private.reports
WHERE status = 'queued'
ORDER BY created_at
LIMIT 50;
```

Inspect the selected report and its audit before acting:

```sql
SELECT * FROM bound_moderation_private.reports WHERE id = '<report UUID>'::uuid;
SELECT action, reviewer, created_at
FROM bound_moderation_private.review_audit
WHERE report = '<report UUID>'::uuid ORDER BY created_at;
```

Replace the placeholder with a queue ID only after review. Choose exactly one:

```sql
SELECT bound_moderation_private.review('<report UUID>'::uuid, 'dismiss');
-- OR 'suspend': stop new invitations/connections/token renewals and deactivate rooms.
-- OR 'reinstate': lift the subject's suspension after review/appeal.
```

Re-read status, audit and the subject's suspension after the chosen action.
Reinstatement removes the restriction without restoring old rooms or erasing
report/audit history. Check support at developer@evanvonessen.com for appeals;
this document invents no staffing, monitoring schedule or response SLA. If a
report lacks evidence, do not label it proven or claim recorded footage exists.
The public policy is `Docs/site/moderation.html`.

## Sharing and filtering limits

Blocking stops the selected local sharing session immediately. Database gates
prevent either party from reconnecting or renewing a token while blocked.
Static legacy rooms cannot bypass the checked friend RPC. New tokens last 60
seconds and the client renews halfway through their lifetime; denied renewal
stops its session. Tokens issued before deployment retain their previous 120
second lifetime. Already issued tokens cannot be revoked by these database
controls; network/SDK timing and modified clients prevent an instant universal
disconnect guarantee. No live paired-device measurement has been completed.

Display-name filtering rejects baseline offensive terms, contact/link text,
control characters and selected invisible/bidirectional formatting. Unsafe
older labels appear as "Friend" while Report/Block remain available. This is
limited text filtering; it does not inspect all live gameplay video. Notes are
local and are not uploaded for moderation.

## Local checks

Use PostgreSQL 17 in an isolated local database: account-deletion `fixture.sql`,
`local-fixture.sql`, `proposed-schema.sql`, `proposed-friend-gates.sql`, then
`contract.test.sql`, all with ON_ERROR_STOP. Fixtures and contract tests are
**never live migrations**. Run `node --test` on both backend handler suites,
the focused Swift checks, and an unsigned Release iPhone build using
Bound.xcodeproj / Bound with committed pins. See the final checkpoint for actual
results and remaining device/network limits.
