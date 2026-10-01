# Locomate for iOS

Native SwiftUI railway journey app. The journey and clustered network maps use Apple MapKit. The interface follows the approved Doop iOS canvas: a full-screen route map, a draggable dark sheet, a floating capsule dock, search, Explore, and Passport.

## Build and test

Requirements: Xcode with an iOS 17 or newer SDK, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project Locomate.xcodeproj -scheme Locomate \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

The 89 Swift tests cover gateway decoding, route geometry, forecasts, date handling, journey plans, source isolation, Passport calculations, and device-only Keychain migration. Two UI tests cover primary navigation and a fresh production launch without sample data. Simulator builds use ad hoc signing so Keychain access is available.

The native app icon uses the same route-shaped L as Android. Its 1024px asset can be regenerated with `swift scripts/render-app-icon.swift`. GitHub Actions runs the simulator tests on the Xcode 27 runner for each pull request.

## Rail data modes

Debug builds default to clearly labeled historical route packs. They provide real route geometry for interface review, but no live position or ETA. Release builds target the deployed SmartRail rail gateway; `LOCOMOTE_RAIL_API_URL` can override the URL when building. The gateway creates an installation-scoped device session; provider credentials stay on the server. Live, predicted, scheduled, stale, and preview data retain separate labels. A production build opens with an empty journey state until a train is selected. A failed production request may show an aged cached run; it does not switch to a preview fixture.

Saved journeys and pending location observations stay on the device: their files are excluded from device backups. Installation identity and gateway sessions use device-only Keychain entries. Route previews are excluded from Passport's saved-run distance, and a forecast is not counted as an observed on-time outcome.

Production sessions, cached runs, journey plans, and Passport entries are scoped to the gateway origin. A development gateway's stored data cannot appear when the app points to production.

A live train position marker requires recent observed evidence from an official, community, or device source. Scheduled or predicted route progress does not create a live marker; historical previews use a separately labeled violet sample marker.

This repository is still under active implementation. Physical-device background location, push delivery, accessibility review, and performance profiling require further verification.
