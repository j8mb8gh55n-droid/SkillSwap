# Direct Messaging migration 05

Run after the existing Phase 3 migrations. The messaging schema depends on
`public.profiles(id)`, `auth.uid()`, the Supabase client roles, and a migration
owner that owns the new tables and RPCs. The hosted project is the production
target. The draft was tested only on a disposable local database.

## Data and permissions

- `chat_conversations` stores one unordered student pair. The original direction
  determines which participant sees Received and which sees Sent. A pending row
  and its first message are created in one transaction.
- `chat_messages` stores the thread, server-assigned author and ID, timestamp,
  and plain text. Bodies must contain non-whitespace text and have at most
  2,000 characters.
- Authenticated clients can read participant rows through RLS. Writes use the
  six narrowly granted RPCs, with the actor derived from `auth.uid()`. No client
  can directly update participants, status, authorship, or read markers.
- Only the original recipient can accept or decline. Acceptance opens both
  directions for sending. A declined or blocked pair cannot start over.
  `chat_block` can create a blocked pair before contact and serializes against
  sends on an existing conversation. Blocking stops contact in both directions.
  It preserves history and has no unblock operation in this draft.
- The two read markers are private columns. `chat_unread_counts` returns only the
  caller's counts, excluding the caller's own messages. Request counts come from
  pending rows. Use the conversation activity timestamp for inbox ordering and
  the message ID for pagination and advancing the read marker.
- There is no exchange foreign key. Resolve optional exchange context from the
  caller's existing participant-scoped exchange data. Exchange state has no
  effect on messaging state.
- Messaging uses in-app inbox counts. The existing notification helper, types,
  and triggers are untouched. Push or system notifications need a separate
  design that addresses deduplication and private message content.
- No reporting or moderation tables were found in the project SQL. A future
  reporting endpoint needs a participant-authorized message reference and a
  moderator-only review path. Blocking is implemented by the RPC.
- The new foreign keys restrict deletion of profiles referenced by messaging
  records. SkillSwap's account-deletion workflow is disabled. Before enabling
  account deletion, decide how to anonymize or retain messaging history.

## Deployment and verification

1. After explicit deployment approval, run `preflight_read_only.sql`. Expect
   all four fields to be true. Check that the deployment role will own the new
   tables and RPCs.
2. Apply `05_direct_messaging.sql` as one transaction. The migration adds only
   messaging objects.
3. Run `verify_read_only.sql`. Expect two RLS-enabled tables, one SELECT policy
   per table, no direct client write grants, hidden cursor columns, and a valid
   unique pair index. Expect six security-definer RPCs with an empty search path
   and execute for authenticated clients only. Both integrity counts should
   be zero.
4. Exercise Supabase Auth, PostgREST, and the two-account workflow in a test
   environment before enabling the app feature.

A failure before commit rolls back the transaction. After deployment, disable
the app entry points and revoke authenticated execute on the six RPCs to pause
writes while retaining existing conversations and messages. If a clean removal
is required, first back up the messaging rows. Drop the six RPCs, then
`chat_messages`, then `chat_conversations`, in one approved transaction.
Dropping the tables deletes messaging history, including declined and blocked
pair records. Reapplying the migration will not recover those records.

## Local test

Use a fresh Docker container with `--network none` and no published ports.
With the existing PostgreSQL 17 image, start it with
`docker run --rm -d --network none --name skillswap-messaging-test -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17`.
After PostgreSQL is ready, run
`python3 supabase/messaging/test_local.py skillswap-messaging-test`, then stop
the disposable container. The tests use synthetic profiles and an Auth shim
with separate database connections for the concurrent introduction test.
Hosted Auth claims, PostgREST and Realtime behavior are outside that test.

## SwiftUI integration

Use the server conversation UUID and message integer ID in the app models.
The current preview models derive IDs locally. Add a Supabase messaging service
for participant-scoped reads, paginated message loading, RPC calls, and inbox
refresh. Select the permitted conversation columns explicitly. Map pending rows
to Received or Sent using the current Auth user ID. Resolve an existing
accepted conversation before offering a new introduction. Use the RPC results
and server state to drive send availability, pending status, and unread styling.
Receiving can start with refresh on open and foreground. Realtime subscriptions
need a later hosted configuration and delivery test.
