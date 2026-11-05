# UI replication progress

Target: official Android v3.1.0. Baseline: a2527e5968af751fd0cf4477a18f186bcdefd3ea, Actions 41950505654, retained IPA. UI branch: ui/android-parity.

## Round 1 — source inventory

- Full Kotlin UI/dependency inventories are recorded alongside ANDROID_IOS_MAP.md. APK manifest and release digest were checked.
- No page is claimed visually complete; baseline differences are explicit in the map.
- Windows packaging baseline: 7 tests pass, 1 existing POSIX symlink fixture skipped by platform; prior macOS baseline ran all 8, core 28 and iOS 92 successfully.
- Next: shared design tokens, exact vector resources and removal of screenshot wallpaper fallback, then all page groups.
- Workspace ruling: native managed worktree request did not return and was aborted. Use independent ui/android-parity branch in the existing source checkout, explicitly addressed by absolute path. Preserve baseline branch/tag; no manual unmanaged worktree was created.

