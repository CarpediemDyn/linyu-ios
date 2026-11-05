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

## Round 4 — wallet and shower

- b9d0f6d: wallet, trend, bills and the source shower layout; active use can be minimized and real stop requires confirmation. Existing BLE settlement and debt calls remain in the model.
- Actions 41981841203 passed the integrated regression and generated visual components for home/device dialogs in both themes at two widths.
- 2b33424 adds test-only wallet/shower captures using the same views and inert callbacks. Compiler errors found in those additions were fixed in 6b3cf78 and 420b1c1 without disabling any tests.

## Round 5 — profile, settings and visual comparison

- 81e4118 and 46f8e2b: inline editing, settings, account and room dialogs, use-code preview, scoped background controls, notification settings, logs, about and update information. Actions 41982432296 passed the integrated regression.
- Official APK login captures: Actions 41981386565. Initial iOS login interaction captures: 41981386963. Measured spacing/shadow differences were corrected in 496c5a6 and reviewed in the next screenshots.
- The first offscreen background render was blank and is not counted as evidence. bdb7472 switches the background capture to a mounted view.
- 6d47c13 exposes already-confirmed device availability to the dialog using the existing query, without changing commands or transport. Added an occupied-device regression case.
- Candidate v0.4.0, build 4, is on UI branch only. 41983206044 passed; its offscreen shower images omitted scroll content and were replaced by mounted captures.

## Round 6 — verified IPA and mounted captures

- Application/test commit: `aab2c635833989884b17c0a515ebfbf416a7b18c`. [Actions 41983779976](https://github.com/CarpediemDyn/linyu-ios/actions/runs/41983779976): 8 packaging, 28 SwiftPM core, 97 iOS unit and 1 iOS UI test passed. No test was bypassed. Physical arm64 Release, ad-hoc seal, strict signature check and packaging passed.
- [IPA artifact](https://github.com/CarpediemDyn/linyu-ios/actions/runs/41983779976/artifacts/13395446207): downloaded and verified all 7 archive members, exact source commit, app icon, iOS Mach-O architecture and SHA-256 `425a4f181112375d5a564a98948bcbc4bd1fc7733d8472c2690ead7e8162e4da`.
- [Simulator attachments](https://github.com/CarpediemDyn/linyu-ios/actions/runs/41983779976/artifacts/13395346979): 39 captures. Mounted shower samples show the device icon, precharge, timer, countdown and stop/closing controls; background capture now includes the page body.
- [Visual QA](VISUAL_QA.md) records which states were compared and which still need authenticated APK references or an iPhone/meter. This is a verified build for user testing, not a claim of complete visual or hardware acceptance.

