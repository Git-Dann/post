# Post

A private, on-device photo editor for iOS 26 — minimal, tactile, and built around a single hero
editing screen with a machined haptic dial.

- **Private by design.** Zero data collection, no tracking, no analytics, no third-party SDKs.
  Everything runs on device. The only (optional) network use is a read-only style-manifest fetch.
- **Adjustments.** Crop, rotation, brightness, contrast, saturation, hue, fades, grain — plus
  one-tap film looks. Non-destructive: edits are a recipe applied live (Metal) and re-rendered at
  full resolution on export.
- **Integrated.** Import via PhotosPicker, save/share via the system sheet, an "Apply a Look"
  App Intent (Shortcuts / Action button), a Share extension, and a Photos editing extension.

## Architecture

- **SwiftUI + `@Observable`**, deployment target **iOS 26.0**.
- **`PostKit`** (local Swift package, `Packages/PostKit`) holds the engine, design system, controls,
  and editor — reused by the app *and* both extensions.
- Rendering: `EditState` recipe → Core Image chain → Metal-backed `MTKView` preview + an export
  actor. Persistence: SwiftData (`Project`) + file-protected originals on disk.

## Build & run

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
# This machine builds with the full Xcode toolchain (xcode-select points at CommandLineTools):
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate
xcodebuild -scheme Post -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
xcodebuild -scheme PostKitTests -destination 'platform=iOS Simulator,OS=26.2' test
```

Then open `Post.xcodeproj` in Xcode to run on a device (needed to feel the haptics).

## Distributing

Which Xcode produced the archive decides whether App Store Connect will take it. The SDK stamp is
baked in at build time, so a rejected archive can never be re-uploaded — it needs rebuilding.

- **TestFlight** accepts a *current* beta toolchain. When Apple ships a new beta, the previous one
  stops being accepted, which is why an upload that worked last month can fail today.
- **App Store submission** needs a release or RC toolchain, never a beta.
- Current lists: <https://developer.apple.com/news/releases/>.

Check an archive before uploading it:

```sh
Tools/preflight-upload.sh          # newest archive, or pass a path
```

The deployment target is iOS 26.0 and there are no availability guards, so a release Xcode can build
this even while development happens on a beta. One caveat if you do: the concurrency annotations in
`PhotosExtension/PhotoEditingViewController.swift` were written against the iOS 27 SDK's
`PHContentEditingController`, so that file is where an older SDK is most likely to complain.

## Layout

- `App/` — app entry, assets, privacy manifest.
- `Library/` — gallery, project store, on-disk storage.
- `Intents/` — App Intents + Shortcuts.
- `ShareExtension/`, `PhotosExtension/` — workflow integrations.
- `Packages/PostKit/` — shared engine + UI.
- `Tests/PostKitTests/` — engine tests (Swift Testing).
