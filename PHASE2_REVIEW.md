# SkillSwap — Phase 2 Review

**Status:** Proposal for approval. No SQL has been executed and no application code has been changed. Creating this document is the only change made.

**Scope:** Backend workflow for student skill exchanges — discover students, view profiles, send requests, accept/decline, schedule sessions, complete exchanges, and view history. Built on the **existing** database (`profiles`, `skills`, `student_skills`, `availability`), which is **not modified**.

---

## 1. Decision Points (from Section 6)

### Decision 1 — Where to collect "learning goal" and "preferred format"
A request can carry an optional **learning goal** and a **preferred format** (online / in person). The current **Request Exchange** screen has neither; the **Schedule Session** screen already asks for format.

- **Option A:** Add a short "learning goal" box and an Online/In-Person toggle to Request Exchange.
- **Option B:** Keep Request Exchange as-is; store goal/format empty for now and capture format at scheduling (where it already exists).

**✅ Recommended: Option B.** Keeps the approved design untouched and avoids asking for the format twice. The database keeps both columns, so Option A can be enabled later with **no schema change**.

**Student experience:** Sending a request stays as quick as it looks today; format is chosen once, at scheduling.

---

### Decision 2 — Where "Confirm Completion" lives
To show finished exchanges in History, the exchange must be marked **completed**. There is no such control today. Completion uses a **two-party confirmation** (see Section 4): each participant confirms from the same place.

- **Recommended:** Add one **"Confirm Completion"** button to the **Exchange Details** screen, shown only after acceptance (and once a session exists), styled like the existing buttons there. No new screen. After a participant confirms, the button reflects "Waiting for the other student to confirm."

**✅ Recommended: add the button to Exchange Details.**

**Student experience:** After the session, each participant taps one clearly-placed button; the exchange moves to Completed/History once both have confirmed. No new screens to learn.

---

### Decision 3 — Whether Explore shows real students now
Explore and student profiles currently show invented people.

- **Option A:** List real signed-up students from the database (the "Featured Skills" strip can remain a curated showcase).
- **Option B:** Keep sample data for now.

**✅ Recommended: Option A.** The exchange workflow requires finding and requesting a **real** person.

**Student experience:** Students see and connect with real classmates. Early on, Explore may look sparse until more people sign up — the existing empty-state design handles this.

---

## 2. Proposed Database Schema (additions only — existing tables untouched)

### Table: `public.exchanges`
One row per exchange request, carried through its whole lifecycle.

| Column | Type | Constraints / Notes |
|---|---|---|
| `id` | uuid | **PK**, `default gen_random_uuid()` |
| `requester_id` | uuid | **NOT NULL**, **FK → profiles(id)** `ON DELETE CASCADE` — who sent the request |
| `recipient_id` | uuid | **NOT NULL**, **FK → profiles(id)** `ON DELETE CASCADE` — who is asked to teach |
| `offered_skill_id` | bigint | **NOT NULL**, **FK → skills(id)** — skill the requester teaches |
| `requested_skill_id` | bigint | **NOT NULL**, **FK → skills(id)** — skill the requester wants to learn |
| `learning_goal` | text | optional |
| `preferred_format` | text | optional; `CHECK (preferred_format IN ('online','in_person'))` |
| `message` | text | optional |
| `status` | text | **NOT NULL** `DEFAULT 'pending'`; `CHECK (status IN ('pending','accepted','declined','completed','cancelled'))` |
| `requester_completed` | boolean | **NOT NULL** `DEFAULT false` — requester's completion confirmation |
| `recipient_completed` | boolean | **NOT NULL** `DEFAULT false` — recipient's completion confirmation |
| `created_at` | timestamptz | **NOT NULL** `DEFAULT now()` |
| `updated_at` | timestamptz | **NOT NULL** `DEFAULT now()` (trigger-maintained) |
| `responded_at` | timestamptz | set when accepted/declined |
| `completed_at` | timestamptz | set when **both** confirmations are true |

**Table-level constraints**
- `CHECK (requester_id <> recipient_id)` — you cannot exchange with yourself.

**Indexes**
- `(recipient_id, status)`, `(requester_id, status)` — fast incoming/outgoing lookups.
- *Recommended optional:* partial unique index `ON (requester_id, recipient_id, requested_skill_id) WHERE status = 'pending'` — prevents duplicate pending requests (anti-spam).

**Relationships**
- `exchanges.requester_id` → `profiles.id`
- `exchanges.recipient_id` → `profiles.id`
- `exchanges.offered_skill_id` → `skills.id`
- `exchanges.requested_skill_id` → `skills.id`

> **Incoming vs outgoing is not stored.** It is computed in the app: `isIncoming = (current user == recipient_id)`.

---

### Table: `public.sessions`
A scheduled session for an accepted exchange.

| Column | Type | Constraints / Notes |
|---|---|---|
| `id` | uuid | **PK**, `default gen_random_uuid()` |
| `exchange_id` | uuid | **NOT NULL**, **FK → exchanges(id)** `ON DELETE CASCADE` |
| `scheduled_at` | timestamptz | **NOT NULL** |
| `duration_minutes` | int | **NOT NULL** `DEFAULT 60`; `CHECK (duration_minutes > 0)` |
| `format` | text | **NOT NULL**; `CHECK (format IN ('online','in_person'))` |
| `location_or_link` | text | meeting link or place |
| `status` | text | **NOT NULL** `DEFAULT 'proposed'`; `CHECK (status IN ('proposed','confirmed','cancelled'))` |
| `proposed_by` | uuid | **NOT NULL**, **FK → profiles(id)** |
| `created_at` | timestamptz | **NOT NULL** `DEFAULT now()` |
| `updated_at` | timestamptz | **NOT NULL** `DEFAULT now()` (trigger-maintained) |

**Index:** `(exchange_id)`.

**Relationships**
- `sessions.exchange_id` → `exchanges.id`
- `sessions.proposed_by` → `profiles.id`

---

### Row Level Security (RLS)

RLS is enabled on both new tables.

**`exchanges`**
- **SELECT** — `USING (auth.uid() IN (requester_id, recipient_id))` — you only see exchanges you're part of.
- **INSERT** — `WITH CHECK (auth.uid() = requester_id AND requester_id <> recipient_id)`.
- **UPDATE** — `USING (auth.uid() IN (requester_id, recipient_id))`; a `BEFORE UPDATE` trigger enforces *who* may do *what* and *which* fields may change (Section 3).
- **DELETE** — not allowed (history is preserved; "cancel" is a status).
- **BEFORE INSERT trigger** (`SECURITY DEFINER`) — verifies `offered_skill_id` is in the requester's `student_skills` with `skill_type = 'teach'`, and `requested_skill_id` is in the recipient's teach set. Prevents fabricated skill claims. (Must be `SECURITY DEFINER` to read both users' `student_skills` regardless of their own RLS.)

**`sessions`**
- **SELECT / UPDATE** — allowed when `EXISTS (SELECT 1 FROM exchanges e WHERE e.id = exchange_id AND auth.uid() IN (e.requester_id, e.recipient_id))`.
- **INSERT** — same participant check **plus** the parent exchange must be `accepted` and `proposed_by = auth.uid()`.
- **DELETE** — not allowed; cancellation via `status = 'cancelled'`.

---

## 3. Status Transitions & Who Can Perform Each Action

### Exchange lifecycle

```
pending ──accept──▶ accepted ──(both confirm)──▶ completed
   │                   │
 decline            cancel
   ▼                   ▼
declined           cancelled
   │
 cancel (requester)
   ▼
cancelled
```

| Transition | Who is allowed | Extra rule enforced by trigger |
|---|---|---|
| `pending → accepted` | **recipient only** | sets `responded_at` |
| `pending → declined` | **recipient only** | sets `responded_at` |
| `pending → cancelled` | **requester only** | — |
| `accepted → cancelled` | either participant | — |
| set `requester_completed = true` | **requester only** (own flag) | only while `status = 'accepted'` **and** a `sessions` row exists |
| set `recipient_completed = true` | **recipient only** (own flag) | only while `status = 'accepted'` **and** a `sessions` row exists |
| `accepted → completed` | **system/trigger** | auto, when **both** completion flags are true; sets `completed_at` |
| any other transition | — | rejected |

**Immutable after insert** (trigger rejects changes): `requester_id`, `recipient_id`, `offered_skill_id`, `requested_skill_id`.
**Field-level guard:** a participant may only flip **their own** completion flag — the trigger rejects a participant attempting to set the other party's flag.

### Session lifecycle
`proposed → confirmed` or `proposed → cancelled`, by a participant of the parent exchange.

---

## 4. How Both Participants Confirm Completion

Completion is **two-sided**, so neither person can falsely close an exchange alone:

1. The exchange must be `accepted` and have at least one `sessions` row (a session was actually scheduled).
2. Each participant taps **"Confirm Completion"** on Exchange Details:
   - the requester sets `requester_completed = true`;
   - the recipient sets `recipient_completed = true`.
   - The trigger allows each person to set **only their own** flag.
3. When **both** flags are true, the trigger sets `status = 'completed'` and `completed_at = now()`.
4. Until the second confirmation arrives, the first confirmer sees "Waiting for the other student to confirm," and the exchange stays `accepted`.

This directly satisfies "prevent falsely completing exchanges": a single party, or a non-participant, can never move an exchange to `completed`.

---

## 5. Support for Future Features (no later restructuring)

| Future feature | How this schema already supports it |
|---|---|
| **SkillSwap Kudos** | A future `kudos (exchange_id → exchanges.id, from_id, to_id, note, created_at)` table. The stable `exchanges.id` and `completed_at` let Kudos be restricted to **completed** exchanges. |
| **Completed exchange counts** | `COUNT(*) FROM exchanges WHERE status = 'completed' AND auth.uid() IN (requester_id, recipient_id)`; indexes on `(participant, status)` keep it fast. |
| **Achievement badges** | Future `badges` + `student_badges` tables, awarded from completed-exchange counts/Kudos. Independent of these tables. |
| **Community Spotlight / monthly top students** | Aggregate completed counts per student per month using `completed_at` — a pure read, no schema change. |
| **Aggregate exchange history** | History = `exchanges` filtered by `status IN ('completed','declined','cancelled')`, scoped to the participant; `created_at`/`completed_at` order it. |
| **Self-reported experience levels** | Future nullable `level` column on `student_skills` (additive); does not touch `exchanges`/`sessions`. |
| **Availability status** | Future nullable column on `profiles` or `availability`; independent. |

None of these require altering `exchanges` or `sessions` later.

---

## 6. Security Risks & Limitations

1. **Insert-validation trigger must be `SECURITY DEFINER`.** To confirm the recipient actually teaches the requested skill, the trigger reads another user's `student_skills`, which their RLS would otherwise hide. It must run as definer and be written carefully (fixed `search_path`) to avoid privilege-escalation mistakes.
2. **Directory visibility is broad by design.** The existing `profiles_select` / `skills_select` / `student_skills_select` policies let any authenticated user read all profiles and skills — required for Explore, but it means profile data is visible to every logged-in student. Acceptable for a campus directory; worth stating explicitly.
3. **Request spam.** Nothing limits how many requests a user sends. Mitigation: the recommended partial unique index blocks duplicate *pending* requests between the same pair/skill; broader rate-limiting would be a future enhancement.
4. **"Session exists" ≠ "session happened."** Completion requires a `sessions` row but not that `scheduled_at` is in the past. If you want stricter proof, add `scheduled_at < now()` (or `status = 'confirmed'`) to the completion rule — a one-line trigger change, flagged as tunable.
5. **Stalled completion.** If one participant never confirms, the exchange stays `accepted` indefinitely (no auto-complete). This is intentional (no false completions) but means some exchanges may linger; a future "nudge"/expiry could help.
6. **Historical skill references.** If a user removes a `teach` skill after an exchange references it, the exchange keeps the original `skill_id` (FK still valid). This is correct for history but means a displayed skill may no longer be in that student's current skill set.
7. **Partial writes on multi-step saves.** Sending a request and syncing skills/availability are separate REST calls; PostgREST has no multi-statement transaction here, so a mid-sequence failure can leave partial state. The app surfaces the error; a future RPC (database function) could make these atomic.
8. **Placeholder availability times (carried from Phase 1).** Availability rows are written with a default `09:00–10:00` window because the current UI captures days only. Real time ranges are a future enhancement and do not affect the exchange tables.
9. **Extension dependency.** `gen_random_uuid()` relies on `pgcrypto`, which Supabase enables by default; the setup SQL will note it.

---

*Prepared for review. On approval, Phase 2 begins with the SQL for you to run (creating `exchanges` and `sessions` with the policies and triggers above), followed by the Swift models, services, and data wiring — with no changes to approved UI designs.*
