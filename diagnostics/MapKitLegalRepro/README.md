# Native MapKit Legal interaction reproduction

This standalone UIKit app contains only an `MKMapView` inside a `UIWindowScene`. It has no SwiftUI sheet, route overlays, annotations, camera padding, application state, or custom hit testing. It is outside the Locomate Xcode project and its routine CI targets.

On 2026-10-02, Xcode 27 / iOS 27 on the iPhone 18 Pro simulator reproduced a non-hittable native `Legal` link in both standard and flat hybrid configurations. One test reported two failed `isHittable` assertions in 13.522 seconds. Coordinate taps at the reported link center left the map visible in both inspected captures. This observation does not establish behavior on other OS versions or physical devices.

Local evidence:

- `/tmp/locomate-pure-uikit-map-credits.log`
- `/tmp/locomate-pure-uikit-map-credits-20261002.xcresult`
- `/tmp/locomate-pure-uikit-map-credits-captures/manifest.json`

Generate and run from this directory, using a fresh result path:

```sh
xcodegen generate
xcodebuild -project MapKitLegalRepro.xcodeproj -scheme MapKitLegalRepro \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/mapkit-legal-repro.xcresult \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

The test deliberately fails when the native link is not hittable and saves its accessibility hierarchy and post-tap screenshot. Do not interpret its presence or the visible credit label as a passing interaction or accessibility result. Locomate preserves MapKit's native credit controls; its opt-in release accessibility gate retains the hit-region assertions and unfiltered audit findings.
