# Native contrast composition diagnostic

This separate target preserves the same near-white footnote text, dark appearance and wording as the app's origin-date hint. All tests run the unsuppressed `.contrast` audit. `testSwiftUIStyle`, `testSwiftUIColor`, `testSwiftUISystem` and `testUIKit` test plain solid-background controls. `testScroll` and `testMapScroll` add a scroll view over a fully opaque dark gradient, with and without MapKit; `testSolidScroll` changes only that reading background to a solid dark color. Screenshots are retained in each xcresult.

On Xcode27.0/iOS27.0, the four plain controls passed. Both gradient scroll cases failed (34 contrast records), while the solid scroll control passed. This supports replacing the app's text-reading gradient surfaces with a solid fill. It does not waive a full app audit or attribute every app issue to the framework. Native MapKit attribution controls and physical VoiceOver remain separate release checks.

Generate with `xcodegen generate -s diagnostics/AccessibilityContrastRepro/project.yml`, then run the ContrastRepro scheme on an audit simulator. The diagnostic target is separate from the shipped app and widget.
