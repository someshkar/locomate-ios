# Locomate for iOS

Native SwiftUI railway journey app. The journey and clustered network maps use Apple MapKit. The interface follows the approved Doop iOS canvas: a full-screen route map, a draggable dark sheet, a floating capsule dock, search, Explore, and Passport.

The [Doop canvas](https://doop.design/c/ha6YK6QvsY) is the visual reference. Its dark palette uses `#060708` ground, `#009DFA` signal blue, `#5FAEF5` route blue, and a 28-point Journey sheet corner radius. The app uses MapKit hybrid imagery for the map.

## Build and test

Requirements: Xcode with an iOS 17 or newer SDK, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project Locomate.xcodeproj -scheme Locomate \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

The routine Swift tests cover gateway decoding, route geometry, forecasts, date handling, journey plans, Live Activity attributes, source isolation, Passport calculations, and device-only Keychain migration. Routine UI tests cover primary navigation and a fresh production launch without sample data. Simulator builds use ad hoc signing so Keychain access is available.

To exercise current public rail data without changing the deployed gateway, start the SmartRail gateway locally with its development secrets and D1 migrations, then run:

```sh
xcodebuild -project Locomate.xcodeproj -scheme Locomate \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:LocomateTests/LocalGatewayIntegrationTests \
  -only-testing:LocomateUITests/NavigationUITests/testCurrentLocalGatewayJourneyAndNetwork \
  LOCOMOTE_LOCAL_GATEWAY_URL=http://127.0.0.1:8787 test
```

These two integration tests are skipped in normal CI. They check search, a dated journey, and the network against the running local Worker.

The native app icon uses the same route-shaped L as Android. Its 1024px asset can be regenerated with `swift scripts/render-app-icon.swift`. GitHub Actions runs the simulator tests on the Xcode 27 runner for each pull request.

## Accessibility release gate

Routine UI tests verify actual Dynamic Type growth from the standard size to the largest accessibility size, reachable tab/search controls, 44-point tap regions (with a 0.001-point floating-point tolerance), and spoken station names plus timetable times. The dock uses native large-content previews when accessibility text sizes require compact icon controls. The magnified Journey label and default/largest layouts were visually checked on the iPhone 18 Pro simulator with iOS 27 and Xcode 27.

The full per-screen XCTest audit is explicitly opt-in and reports every category and every issue without exclusions:

```sh
xcodebuild -project Locomate.xcodeproj -scheme Locomate \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:LocomateUITests/AccessibilityUITests \
  LOCOMATE_RUN_ACCESSIBILITY_AUDITS=1 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

**This gate is still open.** On 2026-10-01 the routine suite passed all 115 Swift tests and six UI tests, including both focused accessibility regressions. Its seven opt-in audits and local-gateway UI test were skipped as configured. When explicitly enabled, all six dark-appearance full audits still failed. Remaining findings include:

- MapKit's 29-by-11-point Legal attribution link and geographic image text with no identified accessibility element. The native map and its accessibility tree are preserved; these are not filtered from the audit.
- A partial Dynamic Type warning for the native navigation-bar Done action.
- Text-clipping warnings for the Passport empty heading, Search explanatory copy/date labels, and contribution headings. Some concern scroll content outside the visible viewport; those findings have **not** all been established as false positives.
- Contrast warnings for the route-status pill, journey stats, and contribution text. Off-viewport content is represented among the findings, and further inspection is required before closing this gate.

Light appearance also has an opt-in Settings audit. Its text/link/status tokens were darkened after measured contrast failures; the full audit result remains a separate gate from those token calculations. The test preserves the original dark appearance after checking light mode.

Simulator auditing does not establish physical VoiceOver focus order, rotor navigation, live notification announcements, or accessibility of the production-only channel/quiet-hours form. Verify those with a current production journey on a physical iPhone before release.

## Rail data modes

Debug builds default to clearly labeled historical route packs. They provide real route geometry for interface review, but no live position or ETA. Release builds target the deployed SmartRail rail gateway; `LOCOMOTE_RAIL_API_URL` can override the URL when building. The gateway creates an installation-scoped device session; provider credentials stay on the server. Live, predicted, scheduled, stale, and preview data retain separate labels. A production build opens with an empty journey state until a train is selected. A failed production request may show an aged cached run; it does not switch to a preview fixture.

Saved journeys and pending location observations stay on the device: their files are excluded from device backups. Installation identity and gateway sessions use device-only Keychain entries. Route previews are excluded from Passport's saved-run distance, and a forecast is not counted as an observed on-time outcome.

Settings offers **Export my data** and **Delete my data**. Export combines the current gateway installation record with Passport, pending observations, preferences, and private files from every local gateway scope. It opens the native share sheet; the exported file is removed when that sheet closes. Deletion first requests gateway erasure, then ends Live Activities, clears consent and local files across scopes, and rotates the device identity. A device-only Keychain deletion marker blocks automatic API sessions, uploads, and alert registration until every deletion step succeeds. A gateway error leaves local saved data in place and keeps that marker for an explicit retry in Settings. Both actions are installation scoped; the app cannot access records created on another device.

Production sessions, cached runs, journey plans, and Passport entries are scoped to the gateway origin. A development gateway's stored data cannot appear when the app points to production.

Community location contribution is opt-in for a current production run. Settings records versioned consent with the gateway before enabling collection, stores failed withdrawal requests for retry, and immediately stops collection and clears queued observations when consent is revoked. Pending observations and withdrawals are scoped to the gateway origin. The collector rejects simulated, stale, inaccurate, and off-route fixes, and uploads fresh batches using the gateway's delta-encoded contract. While collecting, it retries the queue every 30 seconds so restored connectivity does not require another location fix. Foreground collection stops when the app backgrounds unless the separate background option is enabled. Background operation and revocation still need physical-device verification.

A live train position marker requires recent observed evidence from an official, community, or device source. Scheduled or predicted route progress does not create a live marker; historical previews use a separately labeled violet sample marker.

The **Live card** action starts a Lock Screen Live Activity after an explicit tap when the current production run has a known delay. It updates when the app loads fresh run data and marks its ETA stale after ten minutes without a refresh. Server-sent ActivityKit updates still require gateway APNs delivery.

The separate **Journey alerts** control offers observed station progress, delay changes of at least five minutes, platform changes, and actual arrival/departure events. Enabling explicitly requests notification permission and records push consent with the gateway. Optional quiet hours use the chosen IANA time zone and skip events during that interval. Alerts apply to the whole dated train run, independently of the personal boarding/alighting segment and Live card.

Alert choices and pending stop requests are stored atomically per gateway. A foreground retry runs every 30 seconds, with revisions preventing stale registrations from undoing an opt-out. Expired runs and revoked iOS notification permission trigger unregister. APNs tokens are requested each launch and never cached in local files. Notification taps validate the exact run/date, subscription revision, freshness, and route before opening Journey. Privacy export includes preferences and pending mutations; deletion stops registration work before erasing the server installation and removes delivered notifications.

For physical push delivery, enable Push Notifications on `com.locomate.app` in the Apple developer account and provision the target with its `aps-environment` entitlement. Debug uses development signing and the APNs sandbox; Release uses production. Keep `LOCOMATE_APNS_ENVIRONMENT` and `LOCOMATE_APNS_ENTITLEMENT` aligned with the provisioning profile. The gateway also needs its native-alert delivery flag, database migration, and APNs credentials. Simulator navigation and lifecycle tests do not establish delivery on a physical iPhone.

This repository is still under active implementation. Physical-device background location, push delivery, accessibility review, and performance profiling require further verification.
