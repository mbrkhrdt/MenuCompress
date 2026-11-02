#!/bin/zsh
# Builds, notarizes and publishes a MenuCompress release, then adds it to the Sparkle feed.
#
# Bump the version (MARKETING_VERSION) in Xcode and commit, then:
#   scripts/release.sh "What changed in this release"
# The build number is bumped and committed for you when it's needed.
#
# One-time setup:
#   - Be signed in to your developer account in Xcode. The export uses -allowProvisioningUpdates,
#     so Xcode creates the Developer ID Application certificate if you don't have one yet.
#   - Store notarization credentials (an app-specific password from account.apple.com):
#       xcrun notarytool store-credentials MenuCompress-Notary --apple-id <apple id> --team-id WG9DXQASY4
#   - The Sparkle signing key lives in your login keychain under the "menucompress" account.
#     Back it up once; without it, existing installs can never update again:
#       build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account menucompress -x ~/menucompress-sparkle-key
set -euo pipefail

ROOT=${0:A:h:h}
REPO=mbrkhrdt/MenuCompress
TEAM_ID=WG9DXQASY4
NOTARY_PROFILE=${NOTARY_PROFILE:-MenuCompress-Notary}
SPARKLE_ACCOUNT=menucompress
FEED=$ROOT/docs/appcast.xml
OUT=$ROOT/build/release
NOTES=${1:-}

cd "$ROOT"

if [[ $(git branch --show-current) != main ]]; then
    echo "Releases are cut from main." >&2; exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
    echo "Commit or stash your changes first, so the release matches a commit." >&2; exit 1
fi

settings=$(xcodebuild -project MenuCompress.xcodeproj -scheme MenuCompress -configuration Release -showBuildSettings 2> /dev/null)
setting() { awk -v key="$1" '$1 == key && $2 == "=" { print $3; exit }' <<< "$settings" }
VERSION=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
MIN_OS=$(setting MACOSX_DEPLOYMENT_TARGET)
TAG=v$VERSION
ZIP_NAME=MenuCompress-$VERSION.zip

if [[ -z $VERSION || $BUILD != <-> ]]; then
    echo "Couldn't read the version and build number from the project." >&2; exit 1
fi

if gh release view "$TAG" --repo $REPO > /dev/null 2>&1; then
    echo "$TAG already exists on GitHub. Bump the version in Xcode." >&2; exit 1
fi

# Sparkle compares build numbers, so each release needs one higher than anything in the feed.
# A build number that's already ahead (bumped by hand, or left by a run stopped before publishing) is kept.
LATEST_BUILD=$(grep -o '<sparkle:version>[0-9]*' "$FEED" | grep -o '[0-9]*$' | sort -n | tail -1)
LATEST_BUILD=${LATEST_BUILD:-0}
if (( BUILD <= LATEST_BUILD )); then
    BUILD=$(( LATEST_BUILD + 1 ))
    echo "==> Bumping build number to $BUILD"
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/" MenuCompress.xcodeproj/project.pbxproj
    git add MenuCompress.xcodeproj/project.pbxproj
    git commit --quiet -m "Bump build number to $BUILD"
fi

echo "==> Archiving MenuCompress $VERSION ($BUILD)"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild archive -quiet \
    -project MenuCompress.xcodeproj -scheme MenuCompress -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$ROOT/build" \
    -archivePath "$OUT/MenuCompress.xcarchive" \
    -allowProvisioningUpdates

echo "==> Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -quiet \
    -archivePath "$OUT/MenuCompress.xcarchive" \
    -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -allowProvisioningUpdates
APP=$OUT/export/MenuCompress.app

echo "==> Notarizing (this usually takes a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute "$APP"

# Zip the stapled app the way Sparkle recommends, then sign the zip for the feed
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP_NAME"
SIGN_UPDATE=$(find "$ROOT/build/SourcePackages/artifacts" -path '*/Sparkle/bin/sign_update' | head -1)
SIGNATURE=$("$SIGN_UPDATE" --account $SPARKLE_ACCOUNT "$OUT/$ZIP_NAME")

echo
echo "Ready: $OUT/$ZIP_NAME"
if ! read -q "?Publish $TAG to GitHub and push the updated feed? [y/N] "; then
    echo "\nStopped before publishing. Nothing was pushed."; exit 0
fi
echo

echo "==> Publishing $TAG"
git push origin main
gh release create "$TAG" "$OUT/$ZIP_NAME" --repo $REPO --target main \
    --title "MenuCompress $VERSION" --notes "${NOTES:-MenuCompress $VERSION}"

export ITEM="        <item>
            <title>$VERSION</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
            <description><![CDATA[${NOTES:-MenuCompress $VERSION}]]></description>
            <enclosure url=\"https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME\" $SIGNATURE type=\"application/octet-stream\"/>
        </item>"
awk '{ print } /scripts\/release.sh adds each new release/ { print ENVIRON["ITEM"] }' "$FEED" > "$OUT/appcast.xml"
xmllint --noout "$OUT/appcast.xml"
mv "$OUT/appcast.xml" "$FEED"

git add "$FEED"
git commit --quiet -m "Publish MenuCompress $VERSION to the update feed"
git push origin main

echo "==> Done. GitHub Pages usually serves the new feed within a minute or two."
