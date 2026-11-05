# UI replication progress

Target: official Android v3.1.0. Baseline: a2527e5968af751fd0cf4477a18f186bcdefd3ea, Actions 41950505654, retained IPA. UI branch: ui/android-parity.

## Round 1 — source inventory

- Full Kotlin UI/dependency inventories are recorded alongside ANDROID_IOS_MAP.md. APK manifest and release digest were checked.
- No page is claimed visually complete; baseline differences are explicit in the map.
- Windows packaging baseline: 7 tests pass, 1 existing POSIX symlink fixture skipped by platform; prior macOS baseline ran all 8, core 28 and iOS 92 successfully.
- Next: shared design tokens, exact vector resources and removal of screenshot wallpaper fallback, then all page groups.
- Workspace ruling: native managed worktree request did not return and was aborted. Use independent ui/android-parity branch in the existing source checkout, explicitly addressed by absolute path. Preserve baseline branch/tag; no manual unmanaged worktree was created.

## Round 2 — shared design system

- e11a8c6: imported 45 source vector assets, replaced screenshot fallback with a palette background, added shared cards, dialogs, tab strip and theme host.
- Actions 41958011382: 8 packaging, 28 core, 92 iOS tests passed; physical arm64 build and packaging passed. Shared-component intermediate only.
- daab825: addressed code review of theme reveal threshold, independent tab animations and the original white device glyph. Actual animation frames still require comparison.

## Round 3 — login, home, scanner, device dialogs

- 0f75c32: Android source-driven login, home, scanner overlays, device detail, start/failure/retry/deduction dialogs and root navigation/toast wired to existing models.
- Actions 41981172520 passed full existing suite and packaging. This does not verify live camera, BLE or pixel equivalence.
- 28108fc adds real login smoke interactions and screenshot export; Android reference job verifies the official APK before rendering. Screenshot results are not yet accepted.
- Next: wallet/shower and profile/settings integration; measure actual screenshot differences.

