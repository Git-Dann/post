#!/bin/sh
# Report what an .xcarchive was built with, before you spend twenty minutes uploading it.
#
# App Store Connect rejects an upload whose SDK/Xcode stamp isn't on its accepted list, with
# "Unsupported SDK or Xcode version". The stamp is baked in at build time, so re-distributing the same
# archive always fails the same way — you need a fresh archive from an accepted toolchain.
#
# What's accepted:
#   • TestFlight — a *current* beta is fine. When a new beta ships, the previous one stops being
#     accepted, which is the usual reason an upload that worked last month fails today.
#   • App Store submission — needs a release or RC toolchain, never a beta.
# Current lists: https://developer.apple.com/news/releases/
#
# Usage: Tools/preflight-upload.sh [path/to/Foo.xcarchive]     (defaults to the newest archive)

set -eu

archive=${1:-}
if [ -z "$archive" ]; then
    archive=$(ls -td "$HOME"/Library/Developer/Xcode/Archives/*/*.xcarchive 2>/dev/null | head -1 || true)
fi

if [ -z "$archive" ] || [ ! -d "$archive" ]; then
    echo "No archive found. Pass one explicitly, or archive first (Product → Archive)." >&2
    exit 1
fi

plist=$(ls -d "$archive"/Products/Applications/*.app/Info.plist 2>/dev/null | head -1 || true)
if [ -z "$plist" ]; then
    echo "Couldn't find the app's Info.plist inside $archive" >&2
    exit 1
fi

value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || echo "—"; }

echo "Archive          $archive"
echo "Version          $(value CFBundleShortVersionString) ($(value CFBundleVersion))"
echo
echo "Built with"
echo "  Xcode          $(value DTXcode)  build $(value DTXcodeBuild)"
echo "  SDK            $(value DTSDKName)  ($(value DTSDKBuild))"
echo "  Platform       $(value DTPlatformName) $(value DTPlatformVersion)"
echo "  Minimum OS     $(value MinimumOSVersion)"
echo
echo "Toolchains on this Mac"
for app in /Applications/Xcode*.app; do
    [ -d "$app" ] || continue
    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/version.plist" 2>/dev/null || echo "?")
    build=$(/usr/libexec/PlistBuddy -c "Print :ProductBuildVersion" "$app/Contents/version.plist" 2>/dev/null || echo "?")
    marker=""
    [ "$app/Contents/Developer" = "$(xcode-select -p 2>/dev/null)" ] && marker="  ← selected"
    echo "  $version ($build)  $app$marker"
done
echo
echo "Compare the SDK build above against https://developer.apple.com/news/releases/ — if it predates"
echo "the current beta, install that beta and archive again. The stamp cannot be changed after the fact."
