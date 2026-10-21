# SkillSwap — Data Source Ledger (Real vs Mock)

Developer-facing reference. Tracks which features use **real Supabase data** and
which use **mock data** during the UI/UX completion sprint. Keep this updated as
batches land.

Legend: 🟢 Real (Supabase) · 🟡 Mock data · 🟠 Local-only interaction (not persisted) · ⚪️ Not built yet

## Navigation (AppRouter)
| Feature | Source |
|---|---|
| Bottom tabs | 🟢 4 tabs — Home / Explore / Exchanges / Profile (Community removed from nav, files preserved) |
| Cross-tab deep links | 🟢 `AppRouter` env object owns `tab` + payloads; Home category → Explore(category), Home avatar → Profile, Home upcoming → Exchanges+details, Home bell → Notifications |
| Student profile vs My Profile | 🟢 other students → `StudentProfileView` (incl. from Exchange Details); own icon → Profile tab |

## Notifications
| Feature | Source |
|---|---|
| Notifications screen + Home bell + unread dot | 🟢 UI built; reads real data via `NotificationService` |
| Notifications backend (`notifications` table + triggers) | ⚪️ **PENDING MIGRATION** `supabase/phase3_notifications.sql` (not executed) → list is empty / no unread until applied. No mock substituted. |
| Tapping a notification | 🟠 marks read + routes to Exchanges tab; deep-link to the specific exchange pending the write-flow |

## Authentication & Profile
| Feature | Source | Notes |
|---|---|---|
| Login | 🟢 | `SupabaseManager.client.auth.signIn` |
| Sign Up | 🟢 | `auth.signUp` + email-confirmation handling |
| Logout | 🟢 | `AuthManager.signOut` |
| Session persistence | 🟢 | `auth.session` on launch |
| Profile core (name, major, bio) | 🟢 | `profiles` table via `ProfileService`/`ProfileStore` |
| Teaching / learning skills | 🟢 | `student_skills` (skill_type teach/learn) |
| Availability (days) | 🟢 | `availability` table (placeholder 09:00–10:00 times) |
| Forgot Password | 🟢 | `ForgotPasswordView` — `resetPasswordForEmail` → `verifyOTP(.recovery)` → `update(password:)` (Batch D) |
| Password input (show/hide) | 🟢 | functional; SecureField↔TextField focus drop mitigated via re-focus |

## Home — Batch C implemented
| Feature | Source |
|---|---|
| Personalized greeting | 🟢 real name via `ProfileStore` (falls back to "curious mind") |
| Skill Chemistry (mutual matches) | 🟢 uses your real teach/learn skills × 🟡 mock students |
| Upcoming Session card | 🟡 mock → opens real `ExchangeDetailsView` |
| Skills in Demand | 🟡 mock → tap opens `SkillTagSheet` (mock teachers) |
| Skill Roulette | 🟠 local random pick → real `StudentProfileView` |
| Hidden Gems | 🟡 mock → real `StudentProfileView` |
| Upcoming Exchange ("Next up") | 🟢 **real** — next confirmed session from Supabase `sessions`+`exchanges` (`UpcomingSessionService`); empty state when none |
| Pre-sprint sections (featured, quick actions, your skills, exchanges teaser) | 🟡 hardcoded (unchanged, preserved) |

## Explore — redesigned to match Home
| Feature | Source |
|---|---|
| Students (2-col grid, reuses `HomeStudentCard`) | 🟡 shared `MockData.students` (same roster as Home) |
| Featured Skills (gradient cards → `SkillTagSheet`) | 🟡 `MockData.skillsInDemand` (actual skill names) |
| Categories / filters / search | 🟠 local filtering over available data |
| Mutual-match badge + matches-first sort | 🟢 your real teach/learn skills × 🟡 mock students |
| Student Profile (photo passthrough), Request Exchange nav | 🟡 prop-driven mock |
| (Future) real registered-student roster + exclude self | ⚪️ deferred until directory is wired |

## Community (NEW) — Batch B implemented
| Feature | Source |
|---|---|
| Community tab | 🟢 navigation (ContentView, 5 tabs) |
| Feed: Made It / Swap Stories / SkillSnaps + filters | 🟡 `MockData` via `CommunityStore` |
| Appreciations (heart toggle) | 🟠 local (session-only) |
| Comments (view + add) | 🟠 local (session-only) |
| Create Post | 🟠 local (prepends to feed; subtle note shown) |
| Monthly challenge + Join | 🟡 mock / 🟠 local toggle |
| "The Skill Behind It" (tap skill tag → teachers) | 🟡 mock students |
| "Teach Me This" | 🟢 opens real `RequestExchangeView` (send still stubbed) |

## Exchanges — real-data redesign
| Feature | Source |
|---|---|
| My Exchanges = two categories (Requests / Active) | 🟢 **real** Supabase read (`ExchangeService.fetchMyExchanges`); counts derived from data; Completed moved out to History; segmented control |
| Exchange History (dedicated `ExchangeHistoryView`) | 🟢 real read — completed/cancelled/declined, filters All/Completed/Cancelled/Declined, newest-first; reached via circular History icon; read-only details. LIMITATION: no terminal-status timestamp surfaced |
| Exchange Details (redesigned) | 🟢 identity/skills from real data; blurred header; avatar→StudentProfile; top-right glass ⋯ menu (Reschedule/Cancel Session/Cancel Exchange); contextual action by state; "What's Next?" removed |
| Session details (date/time/duration/format/link/status) | 🟢 real fields now carried by `ExchangeService` (`SessionInfo`); shown read-only; proposed-by-other → Accept/Decline; proposer can't self-confirm. Session WRITES still local sim (write-flow pending) |
| Attention banner | ❌ removed (cards + status carry it) |
| Demo fallback exchanges | 🟡 clearly-marked `demoSummaries` — shown ONLY when the real fetch is empty; never presented as real |
| Details navigation (`ExchangeDetailsView`) | 🟢 real summaries → details |
| Accept/decline/schedule/session-confirm WRITES | 🟠 **not wired** — details screen still local simulation |
| Completion (two-party) WRITE | 🟠 **not wired** — DB enforces rules; Swift doesn't call them (see report) |
| **Session cancellation** (Cancel Session) | 🟠 **local simulation** in details (dialog + state: session→cancelled, exchange stays active, re-propose allowed). Real write PENDING. DB already supports it (`sessions` status→cancelled, `sessions_guard`). |
| **Exchange cancellation** (Cancel Exchange) | 🟠 **local simulation** in details (dialog + state→cancelled; shown only for accepted or outgoing-pending). Real write PENDING. DB already supports it (`exchanges_guard`). |
| **In-app notifications** | ⚪️ **PENDING DATABASE MIGRATION** — `supabase/phase3_notifications.sql` prepared (NOT executed). No table/service/bell wiring yet; nothing claimed functional. |
| SkillSwap Kudos | 🟠 local (`KudosView`), inside details |

## Profile — redesigned (blurred header, real sections only)
| Feature | Source |
|---|---|
| Blurred photo header (user avatar → ivory), name, major, bio, Edit Profile, Settings | 🟢 Supabase (`ProfileStore`) |
| Edit Profile = personal info only (photo, name, major, About) | 🟢 Supabase; skills/availability preserved (re-sent unchanged) |
| **Profile photo editing** (PhotosPicker → downscale → upload) | 🟢 code implemented (`ProfileService.uploadAvatar` → Storage `avatars` bucket → `profiles.avatar_url`). ⚪️ **REQUIRES STORAGE MIGRATION** `supabase/phase4_avatar_storage.sql` (bucket + policies, not executed) — upload fails gracefully until applied; existing avatar kept on failure |
| **Skills & Availability** management (`SkillsAvailabilityView`) | 🟢 normalized — catalog chips (`skills`), `student_skills` (teach/learn), `availability` days + a real start/end **time window** (no longer a silent placeholder) |
| Skills I Can Teach / Want to Learn / Availability (read-only on Profile + compact empty states) | 🟢 Supabase |
| Log Out | 🟢 `authManager.signOut` |
| Your Impact stats / Experience / Kudos / Badges / local history | ❌ **removed** — fabricated metrics (completed-exchange counts, kudos, badges) must not be invented; will return only when backed by real data |

## Settings — implemented (gear in Profile)
| Feature | Source |
|---|---|
| Log Out | 🟢 real `authManager.signOut` (confirmation dialog) |
| Change Password | 🟢 real `auth.update(password:)` |
| Account Information / Email | 🟢 live session + `ProfileStore` |
| Contact Support | 🟢 `mailto:` link |
| Notification toggles | 🟠 local `@AppStorage` (persisted on device) |
| Discoverable-in-Explore toggle | 🟠 local `@AppStorage` (not yet enforced server-side) |
| Appearance (Light/Dark/System) | ⚪️ prototype (app pins light; subtle note) |
| Blocked Users | ⚪️ prototype (empty state) |
| Report a Problem | 🟠 local submit (subtle note) |
| Help Center | 🟢 static FAQ content |
| Privacy Policy / Terms | ⚪️ placeholder text |
| Delete Account | ⚪️ **non-destructive** (disabled control + explanation) |

## Batch A — delivered
| File | Status |
|---|---|
| `Theme.swift` | 🟢 shared tokens (new screens only) |
| `SharedComponents.swift` | 🟢 reusable components |
| `MockData.swift` | 🟡 centralized mock content |
| `ContentView.swift` | 🟢 5 tabs (Community added) |
| `CommunityView.swift` | 🟡 styled placeholder |
