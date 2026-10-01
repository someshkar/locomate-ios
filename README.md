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

## Device performance measurement

`LocomatePerformance` is an opt-in Release scheme with the debugger, coverage, GPU validation, and Main Thread Checker disabled. The normal test scheme skips its three tests. It records ten process launches to the first responsive frame using `XCTApplicationLaunchMetric`; the app is terminated between launches, but filesystem and map-tile caches are not purged. A second workload expands and scrolls the journey sheet over the map, collapses it, and opens/closes Search. On iOS 26+, it records app-process hitch and physical-memory metrics. Network loading is completed before measuring that workload.

On a provisioned physical iPhone, use an authorized HTTPS gateway and a dated run it can supply:

```sh
xcodebuild -project Locomate.xcodeproj -scheme LocomatePerformance \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -parallel-testing-enabled NO \
  LOCOMATE_PERFORMANCE_MODE=measure \
  LOCOMATE_PERFORMANCE_GATEWAY_URL=https://your-gateway.example \
  LOCOMATE_PERFORMANCE_TRAIN_NUMBER=12137 \
  LOCOMATE_PERFORMANCE_SERVICE_DATE=2026-10-01 \
  LOCOMATE_APNS_ENVIRONMENT=sandbox LOCOMATE_APNS_ENTITLEMENT=development \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  -resultBundlePath build/LocomatePerformance.xcresult test
```

Replace the run/date, device, team, and gateway with the intended test conditions. The example uses development signing and sandbox APNs while keeping Release optimization; use matching production values with a distribution profile. Provisioning must retain the app's Push Notifications entitlement; the currently configured Personal Team cannot sign it. Each physical result attaches OS/device, supported maximum refresh rate, Low Power Mode, thermal state, and workload context. Establish device-specific baselines only after reviewing the `.xcresult` and Instruments traces on a cool device. Repeated process launches are not a first-install cold-cache measurement. Hitch and memory values alone do not establish 120Hz rendering or 60fps map performance; check actual refresh rate and frame deadlines with Instruments as well. The 400ms launch, zero-jank, memory, and map-frame targets remain unverified.

This simulator dry run validates the same UI interaction path in the optimized build using a labeled historical route pack. It records **no performance metrics or performance pass**:

```sh
xcodebuild -project Locomate.xcodeproj -scheme LocomatePerformance \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO LOCOMATE_PERFORMANCE_MODE=dry-run \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

On 2026-10-01 the Release simulator workload completed successfully (one dry-run test passed; both device measurement tests skipped). This verified sheet expansion, scrolling, collapse, Search presentation, and native grabber dismissal. Log: `/tmp/locomate-ios-performance-dry-run-fixed.log`. It produced no device performance result.

## Accessibility release gate

Routine UI tests verify actual Dynamic Type growth from the standard size to the largest accessibility size, reachable tab/search controls, 44-point tap regions (with a 0.001-point floating-point tolerance), spoken station names plus timetable times, and complete Contribution choices at the largest text size. The dock uses native large-content previews when accessibility text sizes require compact icon controls. The magnified Journey label and default/largest layouts were visually checked on the iPhone 18 Pro simulator with iOS 27 and Xcode 27.

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
- Text-clipping warnings in the original per-screen runs for the Passport empty heading, Search explanatory copy/date labels, and contribution headings. A separate largest-size test now scrolls each passage into the reading region before capturing its bounds and screenshot, then runs the same unsuppressed full audit.
- Contrast warnings for the route-status pill, journey stats, and contribution text. These remain recorded; the full gate is not passed by the narrower visual checks below.

Follow-up inspection at the largest accessibility text size (`UICTContentSizeCategoryAccessibilityXXXL`) established the following:

- The Passport empty heading is fully visible and untruncated at y259–541 in the 874-point viewport. During the audit's Dynamic Type probe the same heading is moved to y571–853, partly below the dock. The recorded clipping warning for that probe is an off-viewport artifact; the screenshot and accessibility label both preserve the whole heading.
- Search's Today chip, origin-date explanation, and historical-snapshot notice are fully readable when scrolled into view. No clipping warnings appeared in the three focused audits of those passages. Other contrast warnings are still reported.
- The contribution card had a real large-text layout problem: its icon and switch narrowed the text enough to split “Contribute” and “background” across lines. Accessibility sizes now put those controls above full-width text and put the consent version below the section heading. The actual row content has a 44-point minimum hit region at ordinary text sizes.
- The visible Route Replay crop contains solid glyph pixels RGB(156,139,255) on RGB(23,26,31), approximately 6.27:1 contrast. This supports readable settled text in that capture; it does not dismiss every status-pill audit warning or establish behavior over all map/appearance transitions.

The initial follow-up screenshots, accessibility bounds, and unsuppressed issues are exported locally under `/tmp/locomate-ios-a11y-visible-passages`; its log is `/tmp/locomate-ios-a11y-visible-passages.log`. After the Contribution fix, `/tmp/locomate-ios-a11y-visible-fixed` shows the foreground row reduced from 782 to 538 points and the background row at 382 points, each fully readable within the 670-point reading region. That focused unsuppressed audit still reports eight findings (seven contrast findings and the Passport clipping probe). No issue handler filters or waives any finding. Remaining framework findings and unproven contrast reports keep the full release gate open.

The follow-up regression run passed `testContributionControlsRespectTextSizeAndHitRegions` and `testPrimarySurfacesOpenOnSimulator` (two tests, zero failures). It verified complete largest-size Contribution rows, disabled preview semantics, ordinary-size 44-point targets, and existing primary navigation. Log: `/tmp/locomate-ios-contribution-regressions.log`; screenshots and bounds: `/tmp/locomate-ios-contribution-regressions`.

The station timeline also wraps long names and stacks scheduled times/metadata at accessibility sizes. Its focused normal/largest-size regression passed and screenshots confirmed the full “MUMBAI DADAR CENTRAL” name and 19:53 time. The spoken label uses “Scheduled time” because the origin row may contain departure time. This is a local layout verification, not a pass of the full audit.

Light appearance also has an opt-in Settings audit. Its text/link/status tokens were darkened after measured contrast failures; the full audit result remains a separate gate from those token calculations. The test preserves the original dark appearance after checking light mode.

Simulator auditing does not establish physical VoiceOver focus order, rotor navigation, live notification announcements, or accessibility of the production-only channel/quiet-hours form. Verify those with a current production journey on a physical iPhone before release.

## Rail data modes

Debug builds default to clearly labeled historical route packs. They provide real route geometry for interface review, but no live position or ETA. Release builds target the deployed SmartRail rail gateway; `LOCOMOTE_RAIL_API_URL` can override the URL when building. The gateway creates an installation-scoped device session; provider credentials stay on the server. Live, predicted, scheduled, stale, and preview data retain separate labels. A production build opens with an empty journey state until a train is selected. A failed production request may show an aged cached run; it does not switch to a preview fixture.

Saved journeys and pending location observations stay on the device: their files are excluded from device backups. Installation identity and gateway sessions use device-only Keychain entries. Route previews are excluded from Passport's saved-run distance, and a forecast is not counted as an observed on-time outcome.

Settings offers **Export my data** and **Delete my data**. Export combines the current gateway installation record with Passport, pending observations, preferences, and private files from every local gateway scope. It opens the native share sheet; the exported file is removed when that sheet closes. Deletion first requests gateway erasure, then ends Live Activities, clears consent and local files across scopes, and rotates the device identity. A device-only Keychain deletion marker blocks automatic API sessions, uploads, and alert registration until every deletion step succeeds. A gateway error leaves local saved data in place and keeps that marker for an explicit retry in Settings. Both actions are installation scoped; the app cannot access records created on another device.

Production sessions, cached runs, journey plans, and Passport entries are scoped to the gateway origin. A development gateway's stored data cannot appear when the app points to production.

Community location contribution is opt-in for a current production run. Settings records versioned consent with the gateway before enabling collection, stores failed withdrawal requests for retry, and immediately stops collection and clears queued observations when consent is revoked. Pending observations and withdrawals are scoped to the gateway origin. The collector rejects simulated, stale, inaccurate, and off-route fixes, and uploads fresh batches using the gateway's delta-encoded contract. While collecting, it retries the queue every 30 seconds so restored connectivity does not require another location fix. Foreground collection stops when the app backgrounds unless the separate background option is enabled. Background operation and revocation still need physical-device verification.

A live train position marker requires recent observed evidence from an official, community, or device source. Scheduled or predicted route progress does not create a live marker; historical previews use a separately labeled violet sample marker.

Explore refreshes once a minute while active and debounces changes to the visible map area. The server's `freshUntil` is enforced independently of request completion: expired positions disappear, including when the device is offline or a fetch is still pending. Invalid/future timestamps, old marker evidence, invalid coordinates, and inconsistent observed-source claims are excluded. Failed refreshes do not extend the prior snapshot's lifetime. Request generations prevent late replies for an older view from replacing current data; source, position kind, name, and timestamp changes update native map annotations even when coordinates stay the same.

Six focused freshness tests passed on 2026-10-01, covering expiry, refresh failure, changed marker metadata, malformed evidence, late replies, and cancellation. The largest-text production overlay check also passed: its header retains its own space while the statistics/source card scrolls through a bounded reading region. Settled screenshots and scroll bounds were inspected; the isolated hosting fixture emits an appearance-transition warning at teardown. This component check does not establish full-screen physical accessibility. Logs: `/tmp/locomate-ios-network-timeline-regressions.log` and `/tmp/locomate-ios-network-overlay-layout-final.log`.

Explore now opens a dated Journey from either a native map callout or the scrollable **View trains** list. Cluster callouts list their members, including trains at identical coordinates; they never choose a member automatically. Each list entry retains the origin date, position kind, source, and update time. Navigation uses validated train-number/origin-date fields, independently of the provider's opaque run ID or displayed name, and rechecks current snapshot membership and freshness at the action boundary. Duplicate marker identities retain the newest eligible observation. Opening a journey does not grant push or location consent.

The focused selection gate passed on 2026-10-01: nine snapshot/selection model tests, one native callout/cluster delegate test, one largest-text overlay check, and one UI test covering standard and largest text sizes. The UI test runs a deterministic loopback service through the ordinary API configuration and verifies that a real list tap reaches the exact dated run endpoint and dismisses the list without consent requests. Its explicit unavailable response establishes routing, not live-feed availability. Normal/largest list screenshots were inspected. Log: `/tmp/locomate-ios-network-selection-final.log`; local evidence: `/tmp/locomate-ios-network-selection-final`. Physical VoiceOver and the unsuppressed full audit remain release gates.

The **Live card** action starts a Lock Screen Live Activity after an explicit tap when the current production run has a known delay. It updates when the app loads fresh run data and marks its ETA stale after ten minutes without a refresh. Server-sent ActivityKit updates still require gateway APNs delivery.

The separate **Journey alerts** control offers observed station progress, delay changes of at least five minutes, platform changes, and actual arrival/departure events. Enabling explicitly requests notification permission and records push consent with the gateway. Optional quiet hours use the chosen IANA time zone and skip events during that interval. Alerts apply to the whole dated train run, independently of the personal boarding/alighting segment and Live card.

Alert choices and pending stop requests are stored atomically per gateway. A foreground retry runs every 30 seconds, with revisions preventing stale registrations from undoing an opt-out. Expired runs and revoked iOS notification permission trigger unregister. APNs tokens are requested each launch and never cached in local files. Notification taps validate the exact run/date, subscription revision, freshness, and route before opening Journey. Privacy export includes preferences and pending mutations; deletion stops registration work before erasing the server installation and removes delivered notifications.

For physical push delivery, enable Push Notifications on `com.locomate.app` in the Apple developer account and provision the target with its `aps-environment` entitlement. Debug uses development signing and the APNs sandbox; Release uses production. Keep `LOCOMATE_APNS_ENVIRONMENT` and `LOCOMATE_APNS_ENTITLEMENT` aligned with the provisioning profile. The gateway also needs its native-alert delivery flag, database migration, and APNs credentials. Simulator navigation and lifecycle tests do not establish delivery on a physical iPhone.

This repository is still under active implementation. Physical-device background location, push delivery, accessibility review, and performance profiling require further verification.
