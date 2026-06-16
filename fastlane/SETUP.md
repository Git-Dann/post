# TestFlight setup (Post)

CI scaffolding for shipping **Post** to TestFlight. The workflow
(`.github/workflows/testflight.yml`) is **manual-dispatch only** until the
steps below are done — it will not run on push yet.

App is uploaded under bundle ID **`co.gitwork.post`** (extensions
`co.gitwork.post.ShareExtension` / `.PhotosExtension`), App Group
`group.co.gitwork.post`. This is a separate app from `foundry-ios`
(`uk.co.gitwork.axisapp`) — different bundle IDs, so nothing is overwritten.

## What's here
- `Gemfile` — pins `fastlane`.
- `fastlane/Fastfile` — `beta` lane: archives the app + both extensions and
  uploads to TestFlight using App Store Connect **API-key cloud signing**
  (matches the project's `CODE_SIGN_STYLE: Automatic`).
- `fastlane/Appfile` — primary app identifier.
- `.github/workflows/testflight.yml` — macOS runner, XcodeGen → archive →
  upload, on `workflow_dispatch`.

## To finish it (off your phone)

1. **Create an App Store Connect API key** (App Store Connect → Users and
   Access → Integrations → App Store Connect API), role **App Manager** or
   **Admin**. Download the `.p8` once.

2. **Add 4 repository secrets** (Settings → Secrets and variables → Actions):
   | Secret | Value |
   |---|---|
   | `APP_STORE_CONNECT_KEY_ID` | the key's Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID |
   | `APP_STORE_CONNECT_KEY_CONTENT` | base64 of the `.p8` (`base64 -i AuthKey_XXXX.p8 \| pbcopy`) |
   | `APPLE_TEAM_ID` | your Apple Team ID (same team as foundry-ios) |

3. **Register in Apple Developer / App Store Connect** (manual, one-time):
   - App IDs for all three bundle IDs, with the **App Groups** capability.
   - The App Group `group.co.gitwork.post`.
   - An **app record** for `co.gitwork.post` in App Store Connect.

4. **Runner with Xcode 27 beta.** Hosted GitHub runners may not carry the
   beta — if the *Select Xcode 27 beta* step fails, point `runs-on` at a
   self-hosted macOS runner that has it installed.

5. **Run it:** Actions → TestFlight → *Run workflow*. To make it automatic on
   every merge to `main`, uncomment the `push:` block in the workflow.

## Alternative: manual flow (like foundry-ios)
If you'd rather mirror the Apex app's hands-on flow instead of CI: add an
`ExportOptions.plist` (`method: app-store-connect`, `signingStyle: automatic`,
your `teamID`), `xcodegen generate`, then archive the `Post` scheme (Release)
in Xcode 27 and Distribute → App Store Connect. No secrets needed.
