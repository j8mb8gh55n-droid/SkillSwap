# SkillSwap publication manifest

The publication candidate is the working tree at `/Users/mac/Downloads/SkillSwap` on `codex/phase-3`. The intended destination is the existing private `j8mb8gh55n-droid/SkillSwap` repository, subject to final approval.

| Include | Reason |
| --- | --- |
| [Application source and assets](../SkillSwap), including [AuthDiagnostics.swift](../SkillSwap/AuthDiagnostics.swift), [LaunchScreen.storyboard](../SkillSwap/LaunchScreen.storyboard), and both [LaunchWordmark files](../SkillSwap/Assets.xcassets/LaunchWordmark.imageset) | The current working tree contains changes beyond HEAD. Include the current app icon and launch art, the two previously untracked LaunchWordmark files, and the required diagnostics source. Include the working-tree removal of the obsolete `SplashView.swift`. |
| [Xcode project and package lockfile](../SkillSwap.xcodeproj) | Project settings and pinned Swift package versions are needed for a reproducible build. |
| [Supabase references](../supabase) and [local tests](../tests) | Preserve tracked migrations, their verification notes, and tests. SQL is organized by purpose in the [README](../README.md). |
| [README](../README.md), this manifest, the two [simulator captures](screenshots), and [.gitignore](../.gitignore) | Submission overview, build instructions, and approved preparation files. |
| Existing tracked project notes | `DATA_SOURCES.md`, `PHASE2_REVIEW.md`, and `documentation/Deferred_UI_Requirements.md` provide historical context. The root README describes the submission build. |

| Exclude | Reason |
| --- | --- |
| `SkillSwap-ChatGPT-Work-Handoff.zip` | Local handoff archive containing duplicate source. |
| `documentation/SkillSwap_Developer_Guide.html` and `documentation/SkillSwap_Developer_Guide_shared.html` | Existing untracked guide variants outside this submission set. Keep them locally for separate review. |
| `build/`, `DerivedData/`, Xcode user state, temporary files and logs | Machine-specific files and generated build products. |
| Private environments, database dumps, backups, signing material and account credentials | Keep outside Git and provide designated demo credentials separately. |

The preflight found no missing application files in the proposed set. The app builds against the existing configured backend. Independent Supabase provisioning still requires a verified baseline for the normalized schema.

Before publication, review the complete staged file list and staged diff, confirm the private destination, and build the staged source. After an approved push, compare the GitHub commit SHA with the approved local SHA and build a separate checkout of that commit.
