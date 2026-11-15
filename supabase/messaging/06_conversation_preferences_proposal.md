# Migration 06 proposal for conversation preferences

Migration 05 stores shared conversation status and separate read cursors. Mute and Delete from Inbox require persistent preferences owned by each participant. Review this proposal before preparing deployment SQL.

## Schema and access

- Add `chat_conversation_preferences` with `conversation_id` referencing the conversation, `student_id` referencing the profile, `muted boolean not null default false`, and nullable `hidden_through_message_id bigint`. Use `(conversation_id, student_id)` as the primary key. A null cursor means visible.
- Enable RLS. Grant authenticated users read access only to their own preference for threads they participate in. Keep direct client writes disabled and revoke access from anonymous users.
- Expose authenticated RPCs to set mute and hide a conversation. Derive the student ID from `auth.uid()` and verify membership before changing anything. Use an empty search path and fully qualified object names for security definer functions. Revoke default execution grants.
- For hiding, lock the accepted conversation row, then capture its highest message ID and upsert the caller’s cursor in that same transaction. Migration 05 sends take that same row lock. Updating the mute flag must preserve the hide cursor, and vice versa.

## App behavior

- Filter hidden threads before inbox pagination. A thread becomes visible when a message newer than the hide cursor exists. Opening a hidden thread from a profile shows its existing history. The thread returns to the inbox when either participant sends a new message.
- Mute leaves the thread visible and preserves message delivery and unread counts. Migration 05 has no message notification trigger. Any future optional chat notifications should check only the recipient’s mute preference.
- Keep Delete from Inbox available for accepted threads only. Shared conversation status, the unique pair index, introductions, and message history stay intact. Label the action Delete and confirm its inbox-only effect.

Verify two-account isolation, denied third-party calls and direct mutations, send/hide ordering under concurrency, and inbox filtering across pages. Rollback would remove the new RPCs and preference table. Export preferences first if they must be retained. Hidden threads would reappear and mute settings would be lost.
