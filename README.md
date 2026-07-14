# Lumae

**Lumae** is a free, offline, native macOS wallpaper manager for static images and video. The name comes from *lumen*: short, modern, and centered on bringing motion and light to the desktop. The repository folder is `lumae-wallpaper`.

> Deployment target: **macOS 14.0 Sonoma**. The project uses Swift 5.10, SwiftUI, AppKit, AVFoundation, Core Graphics, Core Animation, ImageIO, CryptoKit, ServiceManagement, and XcodeGen. It is intended for direct distribution outside the Mac App Store.

## Features

- Native sidebar library with responsive grid/list views, search, sorting, favorites, recent items, missing-file status, drag/drop and file-picker import.
- JPG, JPEG, PNG, HEIC, TIFF, GIF, MP4, MOV and M4V recognition. GIF currently uses its first frame for the desktop surface.
- Original-file references or optional managed-library copies. Removing a library record does not delete the original.
- Local metadata and JSON persistence, SHA-256 duplicate detection, thumbnails, cache cleanup and graceful unsupported/missing-file errors.
- Per-display architecture with stable display fingerprints, duplicate mode and span mode.
- Shared `AVQueuePlayer` + `AVPlayerLooper` timeline for synchronized duplicate/span playback and one `AVPlayerLayer` per display crop.
- Fill, Fit, Stretch and Center geometry; negative desktop coordinates, vertical offsets, rotated-size topology and mixed backing scales are represented in the portable core.
- Non-focusable AppKit wallpaper windows, menu bar commands, settings window, keyboard shortcuts, light/dark appearance and VoiceOver labels.
- No accounts, telemetry, ads, analytics, StoreKit, paid APIs, uploaded media or network requests.

## Architecture

```
Sources/
  LumaeCore/                 Foundation-only models and geometry
  LumaeApp/
    Application/             lifecycle and observable app state
    Views/                   SwiftUI library, display preview, settings
    Services/                persistence, import, display, window, media
    Resources/               plist, entitlements, generated icon assets
Tests/LumaeCoreTests/        XCTest coverage for portable logic
tests/                       Ubuntu-runnable Python geometry parity tests
scripts/                     generation, build, signing, DMG, notarization
project.yml                  XcodeGen specification
Package.swift                portable-core Swift package
```

`LumaeCore` contains no AppKit types. Display rectangles use logical macOS points plus explicit backing scale and pixel dimensions. Platform services translate `NSScreen`/Core Graphics data into those models.

### Wallpaper surfaces

Lumae creates one borderless, mouse-ignoring, non-key `NSWindow` per active display. Its level is `CGWindowLevelForKey(.desktopWindow)`, not a guessed numeric constant. The window joins all Spaces and is stationary/ignored by normal window cycling. Finder/Desktop behavior changes between macOS releases, so icon ordering, Mission Control, Stage Manager and full-screen interactions must be manually verified.

### Seamless video loops and synchronization

A video assignment creates one `AVQueuePlayer` and one `AVPlayerLooper`. All display layers reference that same player, so they share decode, clock, queue transition and loop boundary. Lumae does not seek independent players or recreate windows on every loop. `AVPlayerLooper` prequeues the template item, avoiding the normal end-of-item black frame. Hardware decode is selected by AVFoundation when supported by the codec and hardware.

For independent per-display videos, the architecture permits separate playback sessions; synchronized duplicate and span modes intentionally share one session. Changing wallpaper tears down the looper, removes items and releases layers/windows to prevent hidden-player accumulation.

### Span-mode calculations

1. Union every active display frame in global macOS point coordinates, preserving negative origins and offsets.
2. Normalize display frames into that virtual bounding rectangle.
3. Place the source once in the virtual canvas using Fill/Fit/Stretch/Center.
4. Pixel-align each display viewport using its own backing scale.
5. Intersect each viewport with the global content frame and map that intersection back to source coordinates.
6. Give each display layer the same global content frame translated by that display's virtual origin.

For video, every `AVPlayerLayer` renders a different visible region of the same frame at the same media time. Mixed backing scales can still expose subpixel limitations in Core Animation or display hardware; the portable engine rounds edges to local pixel grids and tests boundary error, but physical seam quality requires Mac hardware testing.

## Ubuntu development limitations

This repository was created in Ubuntu Linux. The environment did **not** contain Swift, Xcode, macOS SDKs or XcodeGen. Consequently:

- The app has not been compiled, launched or profiled on macOS.
- AppKit, AVFoundation, ServiceManagement, signing, notarization and DMG commands could not run here.
- Project structure, plist/XML, shell safety, source consistency, generated PNG assets and portable geometry were validated where possible.
- Python parity tests execute representative layout mathematics on Ubuntu. XCTest remains the authoritative Swift test suite and must run on a Mac.

No macOS-only check is claimed as passed. See `DEVELOPMENT_STATUS.md`.

## Build on macOS

Requirements: macOS 14+, current stable Xcode supporting Swift 5.10 or newer, Xcode command-line tools, Homebrew, and XcodeGen.

```bash
brew install xcodegen create-dmg
./scripts/generate-project.sh
open Lumae.xcodeproj
```

In Xcode, select the **Lumae** scheme and **My Mac**, choose a development team for normal signing, then Build/Run. The app sandbox is disabled because direct-distribution wallpaper/window behavior and arbitrary local-file references are incompatible with a simple sandbox configuration.

Command-line debug build:

```bash
xcodebuild -project Lumae.xcodeproj -scheme Lumae -configuration Debug build
```

## Tests

Ubuntu-available validation:

```bash
./scripts/run-tests.sh
```

On macOS this also runs `swift test` and `xcodebuild test`. The test layouts cover identical side-by-side displays, Retina/non-Retina mixes, above/below layouts, portrait beside landscape, three displays with negative coordinates, reconnection fingerprint matching, mixed-scale span and vertical offsets. Tests also cover duplicate detection, JSON round trips, cache eviction and playlist cycling.

## Release and DMG

```bash
./scripts/build-release.sh                 # build/export/Lumae.app
./scripts/sign-app.sh                      # ad hoc local signature
./scripts/create-dmg.sh                    # dist/Lumae-0.1.0.dmg
./scripts/verify-release.sh
```

The DMG contains `Lumae.app` and an `/Applications` shortcut with a minimal drag-to-install layout.

### Developer ID signing

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
./scripts/sign-app.sh build/export/Lumae.app
./scripts/create-dmg.sh
```

Credentials and identities are never embedded. Hardened runtime is enabled by the project.

### Notarization and stapling

Create a Keychain profile once:

```bash
xcrun notarytool store-credentials LumaeNotary \
  --apple-id 'you@example.com' --team-id 'TEAMID' --password 'app-specific-password'
export NOTARY_PROFILE=LumaeNotary
./scripts/notarize-app.sh dist/Lumae-0.1.0.dmg
./scripts/verify-release.sh
```

`notarize-app.sh` submits, waits, staples and validates. Never commit passwords or profiles.

## Settings and behavior notes

Launch at Login uses `SMAppService.mainApp`, appropriate for modern direct-distribution apps, and reports when System Settings approval is required. Audio is muted by default. Update-check preference is stored, but no updater or network code is included. Playback is paused for screen sleep and inactive login sessions and resumes if previously playing.

Battery, Low Power Mode, full-screen pause, quality and FPS settings are modeled in the UI/persistence but some policy enforcement remains listed as incomplete. Lumae does not pretend those paths are finished.

## Privacy

Lumae is local-only. It performs **zero network requests** in this version. Wallpaper files, hashes, thumbnails, settings and metadata remain on the Mac. There is no account, telemetry, tracking, advertising, analytics, cloud database or update service.

## Known limitations

- macOS desktop-window ordering is semi-documented system behavior and may vary across macOS updates.
- Animated GIF desktop playback is not implemented; the first frame is used.
- The initial assignment UI applies the selected wallpaper broadly; fine-grained per-display editing is represented in models/services but needs additional UI.
- Pause-on-battery, Low Power Mode, full-screen-app detection, explicit decode-quality tuning and enforced FPS limiting need completion.
- Mirrored displays and display IDs without EDID serials use conservative fallbacks; ambiguous matches are intentionally left unassigned.
- AVFoundation codec support depends on the source codec and the Mac. A supported extension does not guarantee every encoded stream is decodable.

## Troubleshooting

- **XcodeGen missing:** `brew install xcodegen`, then regenerate.
- **Wallpaper is above icons:** quit Lumae, capture macOS version/Space/Stage Manager state, and inspect desktop-level behavior; do not raise/lower with arbitrary constants.
- **Video black or unsupported:** test the file in QuickTime Player; transcode to H.264 or HEVC in MP4/MOV.
- **Launch at Login says approval required:** enable Lumae under System Settings → General → Login Items.
- **Gatekeeper rejection:** run `codesign --verify --deep --strict --verbose=2`, then `spctl --assess --type execute --verbose=4` and verify notarization/stapling.
- **Missing wallpaper:** restore the original path or reimport. Lumae does not silently substitute another display's assignment.

## Manual macOS test checklist

Do not mark these complete until actually tested on macOS:

- [ ] Generate project, build Debug/Release, run XCTest, inspect warnings and accessibility audit.
- [ ] First launch, empty/loading/error states, light/dark mode, keyboard navigation and VoiceOver.
- [ ] Import JPG/JPEG/PNG/HEIC/TIFF/GIF/MP4/MOV/M4V; verify unsupported/corrupt files fail clearly.
- [ ] Verify references versus managed copies, duplicates, edits, favorites, missing files, removal semantics and cache cleanup.
- [ ] Test static Fill/Fit/Stretch/Center at Retina resolution without blur.
- [ ] Test video startup, muted/audio behavior, repeated seamless loops, errors and wallpaper changes without leaked players.
- [ ] Test one display; independent assignments; synchronized duplicate; seamless span.
- [ ] Test mixed Retina/non-Retina, mixed aspect ratios/refresh rates, portrait rotation, negative coordinates and vertical offsets.
- [ ] Hot-plug, disconnect/reconnect, arrangement, resolution, scaling and rotation changes without restart.
- [ ] Sleep/wake, lock/unlock, display sleep, lid behavior and disconnected displays.
- [ ] Multiple Spaces, Mission Control, Stage Manager, screen saver and full-screen apps; verify icons remain above wallpaper.
- [ ] Battery/AC and Low Power Mode policies after implementation.
- [ ] Profile CPU, GPU, energy and memory at idle, one video, duplicate and span; run overnight leak test.
- [ ] Launch at Login enable/disable and approval flow.
- [ ] Build app, ad hoc sign, create/mount/copy/eject DMG, verify Applications shortcut.
- [ ] Test unsigned/adhoc Gatekeeper expectations and Developer ID notarized flow on a clean Mac user account.
