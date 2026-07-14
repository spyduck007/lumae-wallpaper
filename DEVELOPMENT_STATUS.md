# Development Status

## Implemented and statically validated on Ubuntu
- XcodeGen project specification, modular source tree, native SwiftUI/AppKit implementation.
- Portable display geometry, span mapping, pixel alignment, assignment restoration, filtering, sorting, duplicate, playlist and cache policies.
- Local JSON persistence, imports, SHA-256 duplicate detection, metadata extraction, thumbnail cache, missing-file detection, managed-copy option.
- Per-display wallpaper windows, static/video rendering, shared AVQueuePlayer/AVPlayerLooper timeline, display topology observation, sleep/session pause and resume.
- Library grid/list, search, favorites, recent/missing sections, drag/drop, settings, menu bar controls, keyboard commands, accessibility labels.
- Dependency-free generated app icon and release scripts.
- Python parity tests for representative monitor layouts.

## Requires compilation on macOS
- Swift compiler and Xcode project generation.
- AppKit/AVFoundation API availability and concurrency diagnostics.
- Asset catalog compilation and application bundle creation.

## Requires runtime testing on macOS
- Desktop window level versus Finder icons across Spaces, Stage Manager, Mission Control and full-screen apps.
- Seamless AVPlayerLooper transitions on Intel and Apple silicon GPUs.
- Mixed Retina/non-Retina span seam behavior, mirrored/rotated displays, hot-plug, sleep/wake, lock/unlock and battery policies.
- Launch-at-login approval flow, long-run memory/CPU/GPU behavior, signing, Gatekeeper, notarization and DMG layout.

## Known incomplete work
- GIF imports are displayed as static first-frame wallpapers; animated GIF playback needs a dedicated ImageIO timeline.
- Frame-rate and quality preferences are persisted but AVFoundation output throttling is not yet enforced.
- Battery, Low Power Mode and full-screen-app pause preferences are modeled; only sleep/session pause is currently active.
- Per-display UI assignment editing is architectural/model-ready but the first UI applies one selected item to all displays.
- Sparkle update integration and release scripts are implemented, but the Ed25519 public key must be generated on the release Mac and the complete install/update path must be tested there.
- Static span uses layered windows rather than replacing macOS desktop pictures; behavior must be verified per macOS release.

## Suggested next steps
1. Generate in XcodeGen and resolve compiler warnings on a Mac.
2. Run the complete manual checklist in README.md on at least one Apple-silicon Mac with two mixed-scale displays.
3. Add power-source/full-screen policy coordinator and animated GIF renderer.
4. Profile shared-player span mode with Instruments and refine CALayer pixel-edge handling.
