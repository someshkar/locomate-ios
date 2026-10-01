# Locomate for iOS

Native SwiftUI railway journey app. The journey and network maps use Apple MapKit. The interface follows the approved Doop iOS canvas: a full-screen route map, a draggable dark sheet, a floating capsule dock, search, Explore, and Passport.

## Build and test

Requirements: Xcode with an iOS 17 or newer SDK, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project Locomate.xcodeproj -scheme Locomate \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  test CODE_SIGNING_ALLOWED=NO
```

The project has 81 Swift tests covering gateway decoding, route geometry, forecasts, date handling, journey plans, and Passport calculations. A separate UI test navigates Journey, Explore, Passport, and Search and captures each screen. Both suites passed on fresh iPhone 18 Pro simulators.

## Rail data modes

The default build uses clearly labeled historical route packs. They provide real route geometry for interface review, but no live position or ETA. To use a deployed SmartRail rail gateway, set `LOCOMOTE_RAIL_API_URL` to its HTTPS base URL when building. The gateway creates an installation-scoped device session; provider credentials stay on the server. Live, predicted, scheduled, stale, and preview data retain separate labels. A failed production request may show an aged cached run; it does not switch to a preview fixture.

Saved journeys stay on the device. Route previews are excluded from Passport's saved-run distance, and a forecast is not counted as an observed on-time outcome.

This repository is still under active implementation. Physical-device background location, push delivery, accessibility review, and performance profiling require further verification.
