# Community Phase 1

Migration 12 creates structured posts, catalog tags, and private bookmarks. A signed-in reader can read every published post, regardless of the author's Explore setting. The request supplies no author identity. The narrowly granted save function derives it from `auth.uid()`, locks ownership through the author-scoped update, and replaces tags atomically. Direct post inserts, edits, and tag writes are denied to clients. Deletion is author-only under RLS. Post and bookmark reads use PostgREST with existing profile and catalog reads.

The existing client does not implement account deletion. Existing exchange FKs can cascade from a deleted profile and existing messaging FKs can prevent profile deletion. This migration changes neither. If a profile is successfully deleted, its Community posts and bookmarks are removed. Post deletion removes tag and bookmark rows. Catalog skills referenced by a post cannot be deleted until those tags are removed.

Limits are a 120-character title, 4,000-character body, 1–10 distinct catalog skills, and one optional 2,048-character HTTPS URL. Links require a dotted hostname, allow only the default HTTPS port, disallow embedded credentials, and open externally. The feed exhausts its UUID cursor pages before local filtering and ordering. For You prioritizes tag overlap with Wants to Learn skill IDs, with latest first for ties and when skills are unavailable. Monitor full-feed download cost before expanding past the demo.

## Local checks

```sh
python3 supabase/community/test_local.py
swiftc SkillSwap/CommunityPostModels.swift tests/community/CommunityPostTests.swift -o /tmp/skillswap-community-swift-tests
/tmp/skillswap-community-swift-tests
```

The PostgreSQL test uses synthetic profiles, an existing-style profile/skill RLS baseline, and a local `postgres:17` image in a disposable container with networking disabled. It does not exercise hosted PostgREST.

## Hosted deployment and rollback

1. Run `preflight_read_only.sql` in the SkillSwap SQL Editor and export its one JSON result. Verify there are no conflicts with the three new relations, indexes, types or save function. Confirm profile and skill keys and the existing profile deletion constraints. Check role inheritance, default grants, and SQL Editor privileges. Verify the preflight baseline before approval.
2. After explicit approval, confirm a private recovery backup, verify the migration checksum, and run the exact SQL once. The migration is transactional. Stop on error and retain the error for review.
3. Run `postflight_read_only.sql`. Verify all three tables have RLS, the six policies and the expected effective grants, column-scoped bookmark inserts, valid constraints and indexes, and the exact save function body. Rerun preflight and compare existing policies, role privileges, and chat/discovery fingerprints.
4. Use a Debug build launched with the argument `--community` so Home and Profile do not need new entry points yet. With the build installed and a simulator booted, use `xcrun simctl launch --terminate-running-process booted fahdah.SkillSwap --community`. Community opens after authentication.
5. Use two approved test accounts. A publishes a tagged post with an HTTPS link, then edits both text and tags. B checks Latest, For You, search and combined filters, opens Post Detail, and saves it. Relaunch B and use Saved only to confirm the bookmark persisted. Unsave and confirm removal. Confirm B has no edit/delete controls and A cannot see B's private bookmark. With A opted out of Explore, verify B can still see A's post. Have A delete the test post, then verify it disappears from B's feed and saved results. Check iPhone 17 Pro presentation, auth failures and retry behavior.

A failed migration rolls back the new objects. After posts or bookmarks exist, prefer disabling access or rolling back the client while retaining the tables and data. Dropping the tables would permanently remove posts, tags and bookmarks. Export the Community data and obtain approval before considering that operation.
