# LinYu Android UI Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox tracking.

**Goal:** Reproduce the complete official v3.1.0 Android UI in the existing iOS project and deliver a verified IPA without changing device/account business behavior.
**Architecture:** Source-driven SwiftUI design system and focused page views calling existing models. Preserve the working build branch, original assets and tests; develop on ui/android-parity.
**Tech Stack:** SwiftUI, UIKit bridges for camera/snapshot rendering, Charts/Canvas, XcodeGen, XCTest, GitHub macOS Actions.
**Spec:** docs/superpowers/specs/2026-11-05-android-ui-parity-design.md

## Global Constraints
- Target official Android v3.1.0, commit a650066a9624681a0e3404063219435d3717fa98, APK SHA-256 recorded in spec.
- iOS 16.0 minimum; keep LiveContainer packaging and arm64 checks.
- No system Form/sheet redesign, screenshot UI, removed cards, fake live data, business protocol changes or skipped tests.
- Original images remain; custom vectors get attribution.
- Full pages, secondary flows, all states and WidgetKit limits remain in scope.

## Review Focus
- Unknown/NaN debt totals must not enable a charge confirmation.
- Theme/background changes must not lose local form/card state or change the other background scope.
- Long device/room labels and small iPhone widths must not overlap controls or conceal end-use actions.
- Preview fixtures must not authenticate, persist orders or execute network/device/payment actions.
- Modal dismissal/navigation must preserve destructive confirmation and current operation state.

### Task 1: Source inventory and baseline preservation
Files: docs/ui-parity/ANDROID_IOS_MAP.md, SOURCE_VERSION.md, source inventories, PROGRESS.md.
- [ ] Read all assigned UI files and their actual dependencies/resources; record read coverage and line references.
- [ ] Verify official APK binary manifest and hash, tagged source and unreleased differences.
- [ ] Preserve successful baseline tag/IPA; create independent UI branch.
- [ ] Commit complete mapping and exact design parameters before view changes.

### Task 2: Shared visual system and resources
Create: Views/DesignSystem/LinYuDesignSystem.swift, LinYuIcons.swift, LinYuThemeHost.swift, Assets.xcassets/Android_*.imageset.
Modify: OriginalRootView.swift only to extract duplicate helpers; OriginalBackgroundPalette.swift for screenshot fallback.
Interfaces: shared interface section in spec is authoritative; publish signatures before page work.
- [ ] Add regression checks showing empty/missing custom background currently renders a screenshot; run to confirm failure.
- [ ] Translate exact palette, glass fill/outline, pill navigation, typography/button/icon/dialog primitives.
- [ ] Import existing XML vector paths with deterministic conversion and source attribution; keep all assets.
- [ ] Implement independent background scopes and single-tree theme reveal.
- [ ] Run relevant regression checks and asset validation, then commit shared system.

### Task 3: Login, home, scanner and device dialogs
Create: OriginalHomeView.swift, OriginalDeviceDialogs.swift. Modify AccountView.swift/OriginalScannerView.swift.
Consumes: shared palette/icons/cards/modals/navigation.
Produces: OriginalHomeView(model:onScan:), OriginalDeviceDetail(model:device:onDismiss:), OriginalStartFailureView(model:failure:onDismiss:).
- [ ] Reproduce complete Kotlin layout, all states and strings from inventory.
- [ ] Keep AuthManager and camera session behavior; reproduce validation/countdown/clear secret controls.
- [ ] Preserve device start/stop gates and reject unknown-total deduction confirmation.
- [ ] Capture login/home/device/scanner state screenshots and inspect compact/large/light/dark.
- [ ] Commit page group with actual evidence and known differences.

### Task 4: Wallet, chart, bill dialogs and shower
Create: OriginalWalletView.swift, OriginalSpendingTrendCard.swift, OriginalShowerView.swift.
Consumes: existing CampusBalanceSnapshot, CampusBill, WaterTransaction and CloudActiveOrder plus shared system.
Produces: OriginalWalletView(model:), OriginalShowerView(model:).
- [ ] Implement balance source/manual edit, complete trend controls and bill states.
- [ ] Reproduce bill detail and charge confirmations with finite known totals.
- [ ] Implement source shower layout, confirmation/result/automatic stop states without protocol changes.
- [ ] Capture all corresponding states and inspect theme/sizes; run original business tests.
- [ ] Commit wallet and shower separately.

### Task 5: Profile, settings and secondary pages
Modify: OriginalProfileView.swift. Create focused files under Views/Profile as needed.
Consumes: shared system; original preferences, model account/code/room methods and logs.
Produces: OriginalProfileView(model:onSettingsVisibilityChanged:) or root-coordinated route binding; agree final route signature before integration.
- [ ] Reproduce account/use-code/room cards and inline editing/ordering/hiding/moving.
- [ ] Reproduce settings, all notification controls, background scope/import/tuning, phone/password dialogs.
- [ ] Reproduce logs/export/about/update states with truthful platform adaptations.
- [ ] Capture all secondary screens/dialogs, theme and small/large layouts; verify navigation hides pill.
- [ ] Commit profile/settings/background page groups.

### Task 6: Root integration, states and visual verification
Modify: OriginalRootView.swift, project-livecontainer.yml, project.yml; add test-only visual harness and screenshot collection workflow.
- [ ] Integrate single live root and all routes; restore toast timing/placement, theme reveal, transitions.
- [ ] Add isolated visual fixtures and capture actual simulator screens; fixture code excluded from Release IPA.
- [ ] Compare each against v3.1.0 evidence, record per-state gaps; fix observed differences and repeat affected captures.
- [ ] Review whole diff for business/test preservation and viewport/action safety.
- [ ] Update full mapping and PROGRESS with evidence, not inferred completion.

### Task 7: Full CI, packaging and handoff
- [ ] Run 8 packaging tests, 28 Swift core tests and complete iOS suite (92 existing cases plus meaningful additions).
- [ ] Fix every actual failure from complete logs; do not suppress tests.
- [ ] Build physical arm64, codesign seal/strict verify, package and upload LinYu-LiveContainer.ipa on UI branch.
- [ ] Download and independently verify manifest/hashes/icon/platform/source; retain baseline separately.
- [ ] Report completed pages, remaining visual/platform/device limits, actual test results and deliverable links.

