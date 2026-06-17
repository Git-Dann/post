# App Store Kit — Post

Draft metadata for App Store Connect. Copy fields verbatim; capture screenshots on device.
Everything here reflects the shipped feature set and the app's zero-data-collection promise — do
not add claims (awards, user counts, "#1/best") we can't back up.

---

## Name & subtitle

- **App Name** (≤30): `Post — Photo Editor` *(19)*
- **Subtitle** (≤30): `Tactile, private photo editing` *(30)*

> "Post" alone is weak for search, so the subtitle carries the category keywords ("photo editing")
> and the differentiators ("tactile", "private"). Keep the brand word first in the name.

## Keywords (≤100 chars, comma-separated, no spaces)

```
filters,film,grain,fade,raw,presets,crop,exposure,contrast,vignette,color,editor,private,offline
```
*(99 chars)* — no trademarked/competitor terms (rejection risk), no word already in the name/subtitle
(those are indexed separately), singular forms (Apple matches plurals automatically).

## Promotional text (≤170 chars, updatable without review)

```
Edit by feel. A machined dial, one-tap film looks, and pro tools — all on-device, with zero
tracking. Your photos never leave your phone.
```
*(150)*

---

## Description (≤4000 chars)

```
Post is a photo editor that feels like a real instrument. Spin a machined haptic dial to grade
your shot, tap a film look, and never hand your photos to anyone — every edit happens entirely on
your device.

PRIVATE BY DESIGN
• No tracking, no analytics, no accounts, no third-party SDKs.
• Your photos never leave your phone. The app works fully offline.
• Optional iCloud sync uses your own private iCloud — we still see nothing.

EDIT BY FEEL
• A tactile tick-dial with real detents and haptics for every adjustment.
• Exposure, brightness, contrast, highlights, shadows, warmth, tint, hue, vibrance, saturation,
  sharpness, vignette, fade and grain.
• One-tap Auto enhance that you can dial back to taste.
• Pinch to inspect at full resolution. Tap to compare against the original.

ONE-TAP LOOKS
• Beautiful film-inspired styles applied instantly — then adjust the strength on the dial.
• Save your own looks and reuse them across photos.

SUBJECT & BACKGROUND
• Confine any adjustment to just the subject or just the background, on-device.

BUILT FOR YOUR PHOTOS
• RAW and ProRAW support, with real latitude in the highlights and shadows.
• Non-destructive: reopen any edit and keep refining.
• Crop, straighten, rotate and flip with Photos-style handles.
• Export as HEIC or JPEG, with location data stripped by default.

FITS YOUR WORKFLOW
• Edit straight from the Share Sheet, inside Apple Photos, or via Shortcuts and the Action button.
• Copy edits from one photo and paste them across many.

Post is designed to get out of the way: image first, tools tactile and minimal, nothing custom that
fights the system. Just you and the photo.

Questions or feedback? dan@gitwork.co.uk
```

## What's New — v1.0

```
The first release of Post.

• Edit by feel with a machined haptic dial
• 15 adjustments, one-tap Auto, and film-inspired looks
• Subject / Background selective edits, on-device
• RAW & ProRAW, non-destructive editing
• Private by design: no tracking, works offline, optional private-iCloud sync

Thanks for trying Post.
```

---

## Privacy nutrition label (App Store Connect → App Privacy)

Select **"Data Not Collected."** Nothing else applies. Confirm against the `PrivacyInfo.xcprivacy`
manifest in the project. Notes that back this up:
- No analytics/tracking SDKs; no network egress except the optional read-only style manifest (never
  uploads user content) and CloudKit (the user's *own* private database).
- iCloud sync is **opt-in** and stores data only in the user's private CloudKit — not collected by us.
- Photos: add-only save + on-device read for import; never transmitted.
- App Tracking Transparency: not applicable (no tracking).

## Screenshot storyboard (6.9" + 6.5" required; 13" iPad if listing iPad)

| # | Shot | Caption |
|---|------|---------|
| 1 | Hero editor, dark canvas, dial mid-grade | `Edit by feel` |
| 2 | A film look applied, styles strip visible | `One-tap looks, dialed to taste` |
| 3 | Subject scope chip + a subject-only adjustment | `Adjust the subject. Or the background.` |
| 4 | Pinch-to-inspect at 100% | `Pixel-peep at full resolution` |
| 5 | Settings privacy panel ("Yours, and only yours") | `Private by design. Zero tracking.` |
| 6 | Gallery grid of projects | `Reopen and refine, anytime` |

Tips: real photos (not stock), keep captions ≤5 words, first two carry the pitch, frame on-device
(no marketing chrome that misrepresents the UI).

---

## Pre-submission checklist (app-specific)

- [ ] **Export compliance** — already declared exempt (`ITSAppUsesNonExemptEncryption = NO`); no prompt expected.
- [ ] **Privacy manifest** — `PrivacyInfo.xcprivacy` present and matches "Data Not Collected".
- [ ] **Permission strings** — Photos add/usage + Camera strings are friendly and accurate (in project.yml).
- [ ] **iCloud (only if shipping sync)** — in the CloudKit Dashboard, **Deploy Schema to Production** before the App Store build, or sync silently no-ops for users.
- [ ] **Category** — Photo & Video (`LSApplicationCategoryType = public.app-category.photography`).
- [ ] **Age rating** — 4+.
- [ ] **Extensions** — Share + Photos editing extensions tested from a real third-party app.
- [ ] **Device QA** — haptics, RAW open, selective mask quality, export-matches-preview, rotation.
- [ ] **Support URL + marketing contact** — required by App Review.
```
