# Phase 3 database changes for review

The Dashboard export is a catalog snapshot. It masks predicate literals, includes
function fingerprints instead of bodies, and contains no application rows. It
reports no Supabase CLI migration ledger. Record the actual deployed definitions
and the approved deployment order before applying these drafts.

## Deployment and rollback

| Draft | Before applying | Verify in staging | Rollback |
| --- | --- | --- | --- |
| 01 Pending request pair | Confirm the existing index predicate. Count pending duplicate groups by requester and recipient. If any exist, stop and agree how to resolve them through normal status transitions. | Concurrent requests for the same directional pair with different skill combinations yield one success and one unique violation. After the pending request is resolved, a new request is allowed. Verify recipient accept and decline and that an unrelated student cannot see either request. | Drop only `public.exchanges_one_pending_per_pair_idx`. The original skill-pair index remains in place. |
| 02 Notification helper grants | Capture the helper's original ACL and function owner, plus its callers and their owners. Confirm the app and any authorized jobs do not invoke the helper directly. | Check that neither client role has effective EXECUTE on the helper. Exercise request, session and kudos events and confirm the expected recipient gets one notification per event. | Restore the captured ACL if rollback is approved. If a trigger owner lost access, prefer restoring access for that specific internal role. |
| 03 Session validation | Capture deployed session guard definitions and confirm the supported client sends meeting details. Count future pending proposals missing those details. Resolve any affected proposals through the normal flow before deploying the guard. | Confirm valid future proposals, reject expired proposals and blank details, and exercise cancellation of legacy rows. Verify proposer self-confirmation and unrelated-user actions remain blocked. | Drop `validate_session_booking_insert_t` and `validate_session_booking_confirm_t` on `public.sessions`, then drop `public.validate_session_booking()`. |

Apply each draft as its own transaction after review. The drafts perform no
backfill. Capture the staging schema and test results between steps.

Optional aggregate checks for an authorized operator during deployment review:

```sql
SELECT count(*) AS duplicate_pending_pairs
FROM (
    SELECT requester_id, recipient_id
    FROM public.exchanges
    WHERE status = 'pending'
    GROUP BY requester_id, recipient_id
    HAVING count(*) > 1
) pairs;

SELECT count(*) AS incomplete_future_proposals
FROM public.sessions
WHERE status = 'proposed'
  AND scheduled_at > statement_timestamp()
  AND nullif(btrim(location_or_link, E' \t\n\r'), '') IS NULL;

SELECT count(*) AS exchanges_with_multiple_future_confirmations
FROM (
    SELECT exchange_id
    FROM public.sessions
    WHERE status = 'confirmed' AND scheduled_at > statement_timestamp()
    GROUP BY exchange_id
    HAVING count(*) > 1
) bookings;
```

## Atomic rescheduling

The deployed session and notification bodies were compared with the local SQL.
The production metadata and aggregate checks found zero duplicate confirmed
bookings, including historical confirmations. Recheck on the intended target
before deployment. Draft 04 aborts if the confirmed-session index cannot be
created. It does not rewrite existing rows.

New proposals record the confirmed future session they would replace. A
participant can decline a proposal without changing the booking. Confirmation
checks the link against the current booking, then cancels the prior row and
confirms the replacement in the same transaction. The old row is retained.
Existing clients can continue to propose, confirm, and cancel using their
current endpoints. A new proposal is refused once the confirmed session has
taken place, so it remains available for completion.

Scheduling writes use a transaction-scoped advisory lock per exchange at
READ COMMITTED. Concurrent writers can receive a retryable failure. Exchange
cancellation closes outstanding proposals and future bookings in the same
transaction and leaves past confirmations intact. Nested cancellation
notifications are suppressed, since replacement confirmation or exchange
cancellation supplies the partner notification.

For rollback, pause scheduling writes. Restore the captured deployed
`notifications_on_session_update()` definition from phase3_notifications.sql
and drop the two `zz_` triggers, their functions, and
`public.sessions_one_confirmed_per_exchange_idx` in one transaction. Keep the
nullable replacement column and foreign key if any replacement has been
accepted. Rollback keeps all booking and notification history. It does not
reactivate a retired booking. Review the affected rows before any corrective
change.

## Local verification

The repository has no staging target configured, and the connected project
returned no Supabase branches. Use a disposable local database for tests.
The single-connection harness uses synthetic profiles and a minimal auth
shim. Run it from the repository with an external temporary PGlite install.

```sh
npm install --prefix /tmp/skillswap-db --no-save --ignore-scripts @electric-sql/pglite@0.5.16
node supabase/phase3_drafts/verify_local.mjs /tmp/skillswap-db/node_modules/@electric-sql/pglite/dist/index.js
```

Run the following concurrent cases using two independent connections to a
disposable PostgreSQL or Supabase test database. Use synthetic participant
accounts and READ COMMITTED transactions.

| Connection A | Connection B while A is open | Verify after both finish |
| --- | --- | --- |
| Insert a pending request and hold the transaction open. | Insert another pending request for the same direction with different skills. | After A commits, B receives SQLSTATE 23505. If A rolls back, B succeeds. |
| Confirm one of two proposals tied to the same future booking and hold the transaction open. | Confirm the other proposal. | B fails or must retry. After A commits, B's retry is rejected as stale. The accepted replacement is the only confirmed row, and the original is retained as cancelled. |
| Confirm a replacement and hold the transaction open. | Cancel the parent exchange, then retry after A commits. Repeat in reverse order. | Once cancellation commits, no future confirmed session or proposal remains. A late confirmation cannot reopen the exchange. Verify each committed transition sends one intended notice. |

Also verify the same trigger behavior on the deployment target, including
direct session cancellation and notification delivery from both accounts.
