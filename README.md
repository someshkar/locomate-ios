# Locomate for iOS

Native SwiftUI railway journey app. The journey and clustered network maps use Apple MapKit. The interface follows the approved Doop iOS canvas: a full-screen route map, a draggable dark sheet, a floating capsule dock, search, Explore, and Passport.

The [Doop canvas](https://doop.design/c/ha6YK6QvsY) is the visual reference. The current native dark palette uses `#060708` ground, `#009DFA` signal blue, `#5FAEF5` route blue, and a 28-point Journey sheet corner radius. The app uses MapKit hybrid imagery for the map.

Main headings use the approved canvas’s native sans-serif fallback: a 32-point heavy system font for Journey, Search, and Explore, and a 34-point Passport heading, with −1.2/−1.3 tracking. These base sizes scale relative to Large Title across Dynamic Type categories. Journey titles have layout priority beside their controls so ordinary text stays on one line; accessibility layouts still put controls beneath the title. Passport’s distance uses the same unrounded, heavier font.

## Shared Passport and Explore layout

Both native repos now use the approved iOS composition: a native map above one rounded, scrollable bottom sheet, with the production dock kept outside the reading area. Explore's heading and source-aware viewport counts share that sheet. At accessibility sizes, the train-list action precedes the statistics so it can be reached without crossing the dock. Passport uses neutral All-Time/year filters and the canvas's deep violet gradient card, a 56-point distance total at ordinary text sizes, 22-point units, and 20-point supporting metrics. Accessibility categories use an adaptive distance layout and vertically stacked metrics.

The Passport map is an unannotated basemap: saved summaries do not contain verified route geometry. MapKit's native attribution stays in the map viewport above the sheet. The map also covers the top safe area; it does not leave an empty band between the map and sheet. The app retains its honest saved-run and source wording, instead of importing the canvas's illustrative network counts or treating saved runs as verified travel.

On 2026-10-01, the final map sizing and navigation layout passed **three simulator cases in 54.871 seconds**: ordinary navigation, largest-text navigation, and an actual HTTP-configured network list opening the exact dated journey at both text sizes. The strengthened network test separately passed in **26.638 seconds**, requiring the complete train-list target to lie inside the reading region above the dock. The dated Save/year-filter flow (**113.347 seconds**) and saved-segment reopening/independent deletion (**88.755 seconds**) passed before the final map-only safe-area/viewport adjustment. Four final navigation/network captures and four earlier hero/year captures were inspected. Current Release simulator build passed. Logs: `/tmp/locomate-ios-overview-final-ui.log`, `/tmp/locomate-ios-overview-network-bounds.log`, `/tmp/locomate-ios-overview-repaired-ui.log`, `/tmp/locomate-ios-overview-actions.log`, `/tmp/locomate-ios-overview-release-build.log`; final captures: `/tmp/locomate-ios-overview-final-captures`. These are focused native layout/behavior checks, not a full accessibility, physical VoiceOver, performance or exact map-imagery parity pass.

## Shared Search page

Search is a primary map-backed page with the floating dock visible, following the shared Doop composition. The native MapKit view stays mounted while the map viewport collapses during typing. The dock follows the keyboard safe area, and the scrollable results reserve its actual footprint. Origin-date chips, historical/source labels, canceled requests, and exact dated Journey selection retain their existing behavior. Search currently supports train names and numbers.

On 2026-10-01, four focused simulator cases passed (77.419 seconds): normal primary navigation, largest-text navigation, keyboard/dock bounds with preview selection, and the complete long train name, number, source, route, and distance at the largest Dynamic Type size. Search screenshots were inspected. The updated Release performance workload also passed its one simulator dry-run case (16.955 seconds), returning through the Journey dock action. These are layout and interaction results; physical performance and the full accessibility gate remain open. Logs: `/tmp/locomate-ios-search-page-final-ui.log` and `/tmp/locomate-ios-search-performance-dryrun.log`; captures: `/tmp/locomate-ios-search-page-final-captures`.

## Shared Journey summary

Journey reuses the map sheet's native material and dark gradient, with a compact 22-point summary card, horizontal station code/time rows at ordinary text sizes, and stacked clocks at accessibility sizes. Full-word departure countdowns emphasize the numbers while keeping their scheduled-boarding qualification. Segment editing appears when details expand. One quiet source-details control replaces the duplicated floating mode/Search badges.

Each summary clock comes from the selected station's actual event, available matched forecast, or scheduled event. Intermediate stops cannot inherit the destination forecast or legacy compatibility arrival. Preview, cached, and stale evidence suppress forecasts; saved clocks retain explicit labels. Scheduled arrival day markers follow the ordered timetable and selected boarding day; clock-only actual/forecast reports do not invent a day offset.

On 2026-10-01, 19 focused Swift cases and three navigation/timeline cases passed before the final map-control cleanup. After that cleanup, three simulator cases passed in **152.429 seconds**, covering normal/largest navigation and the real HTTP future-countdown, Save, and Passport year-filter flow at both text sizes. Four Journey/countdown captures were inspected. The current Release interaction dry run passed (one case, **17.137 seconds**), validating expansion, scrolling, collapse and Search return without recording physical performance. Logs: `/tmp/locomate-ios-journey-card-final.log`, `/tmp/locomate-ios-journey-card-verified.log`, `/tmp/locomate-ios-journey-card-release-dryrun.log`; captures: `/tmp/locomate-ios-journey-card-verified-captures`. Full visual parity, the full accessibility audit, and physical-device checks remain open.

## Journey map controls

The two quiet map actions fit the current dated route or focus its displayed train position. Position labels distinguish historical samples, observations and last-known evidence; hidden evidence disables focus. Each tap is a new command, unchanged commands preserve subsequent manual panning, and commands from a replaced journey cannot focus the new run. Camera padding uses the sheet's screen position. Journey uses flat hybrid imagery to keep long routes out of the globe view. Refreshed station names and coordinates also update native callouts. The source disclosure now appears as “About this data” inside expanded details; spoken summary clocks retain full station names, timing evidence and times.

On 2026-10-01, three native MapKit camera/callout tests passed, including every route coordinate above the sheet, repeated actions, hidden evidence and replaced-journey commands. The normal/largest-text map-action and source-disclosure UI case passed in **37.717 seconds**; all four fit/focus captures were inspected. The spoken-clock/alert regression also passed in the preceding two-case UI run. The optimized Release interaction dry run passed in **18.301 seconds** with no skips or performance metrics. Logs: `/tmp/locomate-ios-map-viewport-final.log`, `/tmp/locomate-ios-map-controls-flow.log`, `/tmp/locomate-ios-map-viewport-release-dryrun.log`; final captures: `/tmp/locomate-ios-map-viewport-final-captures`. These checks do not close the full accessibility, physical performance or visual-parity gates.

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

Debug builds default to clearly labeled historical route packs. They provide real route geometry for interface review, but no live position or ETA. Release builds target the deployed SmartRail rail gateway; `LOCOMOTE_RAIL_API_URL` can override the URL when building. The gateway creates an installation-scoped device session; provider credentials stay on the server. Live, predicted, scheduled, stale, and preview data retain separate labels. A production build opens with an empty journey state until a train is selected for that gateway. A failed production request may show an aged cached run; it does not switch to a preview fixture.

The selected production Journey refreshes when its scene becomes active and every 60 seconds after a refresh completes. Inactive/background scenes and navigation away cancel the request and timer. Refreshes keep the current card and personal stops visible; concurrent requests share the active load, and selection revisions reject late replies even after returning to the same train/date. Failures retain labeled saved data with its cached timestamp and clear on recovery. The position marker and live status expire on a separate evidence deadline even if the network request is still waiting. These reads do not grant alerts, contribution permission, or start a Live Activity.

A known platform is displayed in a separate right-side box for the resolved personal station call and in the station timeline. Unknown and preview platforms are omitted; saved/stale reports say “Last known platform.” At accessibility sizes the badge moves below the full-width station name, remaining right aligned. Normal and largest-size production-card captures confirm the long station name and platform stay readable with vertical scrolling; this is component layout evidence, not a physical VoiceOver pass.

Search results wrap full train names and stack source/route metadata at accessibility sizes. Returning type-ahead results keeps keyboard focus, so the first digits of a train number cannot interrupt entry of the rest; explicit Submit still dismisses the keyboard.

On 2026-10-01 the refresh/platform/Search verification passed **159 Swift tests, three XCTest component/layout tests, and two UI tests**. One opt-in local-gateway integration test was skipped because its external URL was not configured. The seven refresh tests cover visible-state retention, shared requests, cached failure/recovery, A→B→A races, 60-second scheduling, cancellation/resume, interrupted personal-plan restoration, and independent position expiry. The actual app lifecycle test verifies a new dated response immediately after Home→activate with no consent/upload/notification registration calls. The Search UI test enters the full `12951` number, checks its full name at the largest text size, and opens that exact Journey. Log: `/tmp/locomate-ios-refresh-final.log`; normal/large platform, lifecycle, and Search captures: `/tmp/locomate-ios-refresh-final`. The generic iOS Simulator Release build also passed (`/tmp/locomate-ios-refresh-release-build.log`).

The quieter **Reliability history** card in Insights reads the existing train-history summary. Early, on-time (within ±5 minutes), and late percentages use only runs with classifiable final-destination arrival timing; cancelled and unknown runs are excluded and counted separately. It shows the sample size, service-date coverage, report generation time, and partial-coverage disclosure. Fewer than ten classified arrivals receive a small-sample note. A zero denominator shows unavailable percentages, including when recorded runs exist but their arrival timing is unknown. These historical outcomes do not predict the selected journey or its personal alighting stop.

History requests use `limit=1`; the server's aggregate summary covers its eligible records independently of that one-row page. Fractional arrival delays decode without discarding the response. The client validates the train identity, count/percentage relationships, policy, provenance, dates, and generated timestamp before display. The card loads separately from live Journey refresh, with explicit loading, error, empty, and manual retry states. Requests and visible results belong to the current train/date/service; cancellation and a pending privacy deletion discard late responses. Preview mode sends no history request, and viewing history creates no new consent, contribution, alert subscription, or Live Activity.

On 2026-10-01 the focused history gate passed **seven Swift tests and one UI test** (68.636 seconds). The tests cover fractional-delay decoding, aggregate denominators, empty/unknown-only summaries, invalid contracts, request ownership, retry, preview/privacy blocking, and cancellation. The UI test uses the ordinary API configuration with a deterministic loopback server, exercises error→retry→summary and cold relaunch at the largest text size, then verifies unknown-only data retains coverage and exclusions without inventing a percentage. Exact request paths and absence of consent/upload/notification writes are asserted. Log: `/tmp/locomate-ios-history-verified.log`. All eight screenshots were exported to `/tmp/locomate-ios-history-final/manifest.json`; normal, largest-text on-time, sample, exclusions, coverage, small-sample, partial-disclosure, and unknown-only captures were inspected. This is focused simulator layout evidence, not a full accessibility or physical VoiceOver pass. The generic iOS Simulator Release build passed (`/tmp/locomate-ios-history-release-build.log`).

On 2026-10-01, the final typography navigation run passed **two UI tests** (32.311 seconds): all primary surfaces at normal text, followed by actual growth to the largest accessibility size with reachable navigation and Search. The long-name Search case also passed (35.588 seconds) in the preceding run; the subsequent fix changes only Journey heading width allocation. Seven of nine exported final navigation screenshots were inspected. Logs: `/tmp/locomate-ios-heading-alignment-verified.log` and `/tmp/locomate-ios-heading-alignment-final.log`; final captures: `/tmp/locomate-ios-heading-final/manifest.json`. The generic Simulator Release build passed (`/tmp/locomate-ios-heading-release-build.log`). These are focused typography/layout checks; the separate full accessibility and physical-device gates remain open.

The dock now uses the reference's compact 330-point footprint, outline train/globe/passport icons, neutral white selection, and separate 60-point Search circle. iOS 26 and later use native clear Liquid Glass in one `GlassEffectContainer`; older versions retain the material/tint fallback, and Reduce Transparency uses a solid surface. The effect wraps the complete controls so their foreground remains sharp. Accessibility sizes keep named actions and the native large-content viewer without wrapping dock captions. Journey actions use two columns at accessibility sizes to give Save, Calendar, Share, and Live card enough width.

The final dock run passed **three simulator UI tests** (142.932 seconds): normal navigation, largest-text navigation/Search, and the real HTTP dated-run Save/Passport flow at both text sizes. The latter keeps full control bounds above the dock and verifies current/previous-year filtering. Five final captures were inspected. The timeline test also passed (55.919 seconds) in the preceding run after selecting its actual Punjab Mail route explicitly; a previous Search selection must not change that test's timetable. Scroll helpers now handle absent offscreen snapshots and allow enough bounded scrolling for the largest text. Logs: `/tmp/locomate-ios-dock-final.log`, `/tmp/locomate-ios-dock-navigation.log`; final captures: `/tmp/locomate-ios-dock-final-captures/manifest.json`. The current generic Simulator Release build passed (`/tmp/locomate-ios-dock-release-build.log`). Full hosted CI, physical accessibility/performance, and complete visual parity require their separate evidence.

Saved journeys and pending location observations stay on the device: their files are excluded from device backups. Installation identity and gateway sessions use device-only Keychain entries. Route previews are excluded from Passport's saved-run distance, and a forecast is not counted as an observed on-time outcome.

Settings offers **Export my data** and **Delete my data**. Export combines the current gateway installation record with Passport, pending observations, preferences, and private files from every local gateway scope. It opens the native share sheet; the exported file is removed when that sheet closes. Deletion first requests gateway erasure, then ends Live Activities, clears consent and local files across scopes, and rotates the device identity. A device-only Keychain deletion marker blocks automatic API sessions, uploads, and alert registration until every deletion step succeeds. A gateway error leaves local saved data in place and keeps that marker for an explicit retry in Settings. Both actions are installation scoped; the app cannot access records created on another device.

Production sessions, cached runs, journey plans, and Passport entries are scoped to the gateway origin. A development gateway's stored data cannot appear when the app points to production.

The last selected train number and India origin date are stored atomically per gateway (with a separate preview scope), excluded from device backups, and included in privacy export/erasure. Search, Explore, direct links, and accepted notification routes update that reference. A cold launch restores it through the usual live/cache loader; an explicit incoming route takes precedence. A different source starts with its own selection, and a pending privacy deletion blocks restoration. Successful deletion clears selections across every source, while invalidated old services cannot rewrite them. The run-cache decoder uses the same ISO date representation as the encoder, allowing the last production response to load after a failed refresh.

Restoration does not enable journey alerts, create a new Live Activity, or start contribution. A later explicit journey selection or successful foreground-contribution consent action can activate the existing contribution policy; an already saved consent flag alone does not trigger collection from a restored view. No consent preferences are changed by restoring a route.

An offline cached card and map header say **Saved journey**, use the stale status style, and do not pulse as live. Scheduled times remain timetable values. For a future personal boarding stop with a known scheduled departure, the card uses full-word units such as “1 day 4 hours until scheduled departure.” The calculation follows the dated timetable across midnight; previews, passed stops, and recorded actual departures do not show a countdown. Cached countdowns also say **Saved timetable**. Delay text uses phrases such as “18 minutes late,” retaining estimated or stale qualifiers.

Passport offers **All-Time** and **Train origin year** filters. The selected period updates both saved-run rows and summary totals, using the train's India origin date rather than the save date. Preview and legacy source-unknown entries remain in All-Time; previews are identified and excluded from real-run distance totals. Saved runs do not establish completed travel.

Each valid Passport row has separate **Open journey** and Remove actions. Opening uses the same dated route loader and durable selection as Search/Explore, and restores the personal segment captured when the row was saved. Later edits to the working plan do not replace that saved segment. Older records can restore a uniquely matching saved station sequence; if the timetable no longer identifies it safely, the app explicitly shows the full route and asks the traveller to choose stops again. Source-unknown or invalid dated records cannot open a different source's route. Opening does not enable alerts or grant contribution consent. Statistics and full saved train names wrap at accessibility text sizes.

Newly saved durations follow every scheduled call from personal boarding departure to drop-off arrival, including multiple midnight crossings. A missing personal schedule is shown as **Duration unavailable** rather than borrowing the whole run's duration; the aggregate shows a dash when it has no known minutes. Known short segments show minutes. Existing saved records remain readable without a migration.

The Journey station card resolves one call within the personal segment and labels its own scheduled, actual, or estimated time. A destination forecast cannot be displayed as an intermediate next-stop arrival. Cached reports retain saved/stale wording; preview boarding remains timetable-only.

The follow-up Passport/station gate on 2026-10-01 passed **33 focused Swift cases and one UI case** across the combined run and an exact-case correction. The new tests include three saved-segment reopening cases, ten station-evidence cases, and three duration cases: the captured full run is 2,020 minutes; personal segments retain each relevant midnight crossing; missing personal timing stays unavailable. One old test expected the bundled route to take roughly ten hours despite its day-three arrival; its corrected 2,040-minute assertion passed in the exact retry. Logs: `/tmp/locomate-ios-passport-reopen.log` (32 of 33 Swift cases and the UI case passed) and `/tmp/locomate-ios-passport-duration-exact.log` (the corrected Swift case executed and passed). An earlier method selector matched zero tests and is not counted as verification.

The saved-row UI case passed in 89.405 seconds through the ordinary loopback gateway configuration: Edit and Save a non-default segment, edit the working plan again, reopen the actual saved row at the largest text size, verify the dated request and original segment, and remove the row without navigation or consent requests. Seven screenshots were inspected under `/tmp/locomate-ios-passport-reopen`: ordinary and largest text train names, complete statistic captions, separate Open/Remove targets, and the reopened Dadar–Kalyan segment. This remains a focused simulator check; the full audit and physical VoiceOver gates are still open.

On 2026-10-01 the combined focused run passed all 17 Swift tests: five restoration, five status-copy, five natural-language, and two Passport-period cases. The cold-relaunch UI test also passed (37.388 seconds). Restoration checks cover source isolation, validated storage, backup exclusion/export, deletion blocking, ISO-date cache round-trip, a fresh model's offline recovery and saved label, and explicit consent after restoration. The UI check terminates the real app, switches between two loopback gateway sources, restores a captured production run after a failed gateway refresh, verifies **Saved journey**, opens a competing cold-launch URL, and deletes through ordinary Settings before another empty relaunch. These deterministic responses test app storage/navigation, not current rail-feed availability. Log: `/tmp/locomate-ios-restoration-timetable-final.log`; visually inspected cached screenshot: `/tmp/locomate-ios-restoration-timetable-final/753CE20D-C7C2-4707-93A4-975054CC62B5.png`.

The combined command initially failed in the timetable/Passport UI test because its scrolling gesture activated a train-list action. The focused test now enters its two runs through ordinary dated URLs and scrolls from the content gutter, preserving the real gateway, countdown, Save, selected-year, and visible-row assertions. Its exact-case retry passed at both normal and largest accessibility text sizes (one test, 119.087 seconds). Final focused coverage is **17 Swift tests and two UI tests passed** across the combined run and that retry. Log: `/tmp/locomate-ios-timetable-passport-focused.log`; screenshot evidence: `/tmp/locomate-ios-timetable-passport-passed`. This did not rerun or close the separate full accessibility or physical-device release gates.

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
