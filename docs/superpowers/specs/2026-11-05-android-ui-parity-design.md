# LinYu Android v3.1.0 UI parity design

## Binding request
Replicate all Android v3.1.0 interfaces in the existing SwiftUI iOS project. This is source-led UI reproduction, not redesign. Preserve original navigation, hierarchy, text, assets, geometry, colors, state handling, confirmations and animation. Preserve network, BLE, transaction and account implementations. Do not replace interactive UI with screenshots or ship fake account/device data.

The user supplied the six-stage execution sequence and confirmed official v3.1.0 as the target. Follow this specification continuously; ask only for genuinely missing external inputs.

## Baselines and evidence
- iOS baseline: a2527e5968af751fd0cf4477a18f186bcdefd3ea; green Actions 41950505654; baseline IPA retained.
- Development branch: ui/android-parity; build/livecontainer stays at its working baseline until review/acceptance.
- Android source: v3.1.0^{commit} = a650066a9624681a0e3404063219435d3717fa98.
- Official APK: linyu-v3.1.0.apk, versionCode 16, package com.hualala.linyu; SHA-256 5212f96c856b9d91388511d33533d8122dd5d1481863bd671909602a599163aa. Version verified from binary AndroidManifest.xml, not just the release title.
- Existing Android checkout ff5f8be contains unreleased 3.1.1 business fixes. UI source is unchanged except MainViewModel; preview.png also differs. Extract tagged preview for reference.
- Full source inventories live in docs/ui-parity. Every requirement keeps an explicit implementation/visual/functional verification status.

## Approach
Use real SwiftUI components with values and layout translated from Kotlin Compose, keeping existing models as adapters. Reuse Android custom vector paths and app_logo; convert drawable XML to vector asset catalogs, retaining source attribution. Android material icons should use equivalent original Material path assets, not unrelated SF Symbols. Emoji remain only where Android intentionally uses emoji.
Alternatives rejected: UIKit system Form/sheet substitutions change the design; screenshot backgrounds are not interactive and duplicate UI. Existing bg_home/bg_settings/bg_shower files are reference screenshots, not default wallpaper; retain files without rendering them as live background.

## Shared design interfaces
Create LinYuIOS/Views/DesignSystem/LinYuDesignSystem.swift:
- LinYuPalette: background, card, solidSurface, primary, accent, textPrimary, textSecondary, success, warning, danger, activeBackground, surfaceVariant, border, isDark.
- EnvironmentValues.linYuColors supplies palette; LinYuThemeHost(preferences:content:) observes existing preferences and injects it.
- LinYuIcon(name:String,size:CGFloat=24) renders Android_<drawable-name> template assets; LinYuDeviceGlyph(emoji:String,size:CGFloat=24) maps shower/sink, fallback only for original emoji types.
- OriginalGlassCard(padding:CGFloat=20,cornerRadius:CGFloat=22,content:) uses original palette RGBA fill and 0.8-point outline. No system Material replacing original RGBA.
- LinYuButtonStyle, LinYuOutlinedButtonStyle, LinYuIconButton and LinYuSectionTitle provide original styles.
- LinYuModal(isPresented:content:) is a view modifier for centered original dialogs with scrim, max width 560, 28 radius, 24 padding. Dialogs own their original buttons; destructive controls remain explicit.
- LinYuPillNavigation(selection:) is 260 wide, 4 inset, 42-high horizontal icon/title items, 28 outer/22 inner radius, spring ratio .72/stiffness 380, 200ms text transition.
- OriginalBackground(preferences:shower:) draws custom image only when a selected image exists. No screenshot fallback. Home background base F1F5F9/0E131D; shower uses ShowerScreen gradient unless custom image enabled.
- Theme reveal uses one live content tree, 650ms cubic(.4,0,.2,1), old background mask and content switch at 20%, retaining state.

## Page responsibilities
- AccountView.swift: original blue gradient and white login card, SMS/password modes, autofill, clear fields, fixed 84 send button, countdown, request progress, 13pt error surface, clear secrets after login attempt.
- OriginalHomeView.swift: exact heading/action row, in-use orders, last device, nearby section, RSSI legend, scan/error/empty states and device rows. Calls existing model methods.
- OriginalDeviceDialogs.swift: device details, cloud/BLE choice when required, start failure, debt preview/confirmation, automatic close notice. Invalid totals cannot authorize a deduction.
- OriginalWalletView.swift: source balance, manual estimate dialog, trend card, bill list and bill detail. Do not invent replacement summaries or omit balance-source explanations.
- OriginalSpendingTrendCard.swift: collapse, summary metrics, 7 days/month, bar/line, selection and peak annotation, empty/error states.
- OriginalShowerView.swift: original giant control composition, device, pre-withhold, timer chip, auto-close panel, end confirmation and result states.
- OriginalProfileView.swift plus focused settings files: original card-based account/use code/room pages, settings navigation with pill hidden, inline account editing, independent card ordering/hiding/moving, all existing actions preserved.
- OriginalScannerView.swift: keep working AVFoundation/Vision camera code, reproduce Android overlay/header/frame/torch/gallery/invalid/error states.
- OriginalRootView.swift only coordinates theme, routes, navigation, custom modal presentation, toasts and model lifecycle; it must not redefine the extracted page types.

## Builder-check rulings and integration contract
- LinYuModal is a ViewModifier: init(isPresented: Binding<Bool>, canDismiss: Bool = true, onDismiss: @escaping () -> Void = {}, @ViewBuilder content: () -> Content). Scrim consumes input and accessibility marks the modal; busy dialogs set canDismiss=false. Only one root transactional modal is presented at a time.
- OriginalProfileView(model:onSettingsVisibilityChanged:) has callback (Bool)->Void, default no-op. It reports true for settings/background routes and false on return/disappear. Root owns pill visibility. OriginalShowerView(model:onBack:) takes a closure that clears only the presentation IDs; root displays it inline, with pill hidden. OriginalHomeView(model:onScan:) owns no root routes.
- Root resets selected tab after successful login. Existing owner/nonce checks for URL actions remain authoritative; no unverified replay or new control commands are introduced for UI parity.
- Freeze choose/transport/session implementations. iOS must establish BLE identity through its existing adapter because CoreBluetooth does not expose Android MAC scanning; document this necessary platform wait. Expired sessions remain immediately invalidated for safety; the view can retain and display the failure notice after invalidation, without retaining usable credentials. UI logout is gated while any order is active or an operation is busy. These are presentation guards, not a new account/transaction engine.
- Show actual settled amounts only when a matched existing model supplies them. Unknown amounts remain unknown and cannot authorize deductions; no inferred bill matching or invented completion data.
- LinYuType.font(size:weight:) centralizes explicit numeric font sizes and line spacing. Android default system font may vary by device; record the actual reference/simulator typography difference rather than claiming universal font identity.
- Visual fixture views consume plain presentation values and inert callbacks. They do not instantiate OriginalAppModel/AuthManager or write Keychain/UserDefaults/orders/notifications. Keep fixture data in test files, not production classes; Release excludes the test target entirely.
- Screenshot IDs use page/state/theme/viewport; each row records Android source/APK capture availability separately from iOS output. Missing APK images stay visually unverified. WidgetKit support/limitations are a required explicit document in Task 6, not an implicit completed port.

## Safety and platform differences
Keep existing QzxyAPI, OriginalFeatureAPI, BLE transport, WaterTransactionEngine, CloudShowerController and credentials intact. Presentation validation may prevent unknown-amount confirmation but cannot fabricate amounts or bypass server guards.
Keep current user settings and storage keys. Photo background controls affect only selected scope. No real login, payment or valve actuation during visual QA.
iOS cannot install Android APK updates or provide Android foreground-service guarantees after force quit. Show truthful iOS update/distribution information in the corresponding original card/dialog.
WidgetKit is assessed separately: supported families and deeplink actions only; no claim of Android size identity, continuous scans, or guaranteed background valve operations. LiveContainer package continues excluding widget extension.
Visual fixtures stay test-only, unauthenticated and transient; never write sample credentials/device orders into production persistence.

## Validation and acceptance
All original states and routes remain in the mapping table until visibly checked. Compile success alone never means UI parity. Capture real iOS simulator screenshots for each route/state at compact and large iPhone sizes in light/dark; compare against tagged Android preview and actual APK captures wherever available. Record unavailable Android state captures and remaining differences explicitly.
Run full existing core, API, crypto and packaging tests, add meaningful presentation safety/visual coverage, build physical arm64 Release, ad-hoc seal/verify, package actual IPA, check hashes and source commit. No test suppression.
Commit by shared components and page groups, publish each round's completed pages/differences/test evidence/next work in docs/ui-parity/PROGRESS.md.

