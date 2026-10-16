#!/bin/bash
# Builds Yapper for Mac on your own Mac and zips it.
#
#   scripts/mac-release.sh            test build (ad-hoc signed: testers right-click › Open)
#   scripts/mac-release.sh --sign     signed with your Developer ID and notarized by Apple,
#                                     so it opens with a double-click on any Mac
#
# Needs Xcode 26 and XcodeGen (`brew install xcodegen`). --sign also needs a
# "Developer ID Application" certificate in your keychain and a notary
# profile saved once with:
#   xcrun notarytool store-credentials yapper-notary --apple-id <you> --team-id 52GURPQBA2
# The zip lands in build/mac/.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN=false
[ "${1:-}" = "--sign" ] && SIGN=true
PROFILE="${NOTARY_PROFILE:-yapper-notary}"
OUT=build/mac
VERSION="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-0.1}"

xcodegen generate --spec project.yml
RESOLVED="Yapper.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$RESOLVED")"
cp Package.resolved "$RESOLVED"

if $SIGN; then
    IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
    if [ -z "$IDENTITY" ]; then
        echo "No Developer ID Application certificate in your keychain." >&2
        exit 1
    fi
    SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" DEVELOPMENT_TEAM=52GURPQBA2
             OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

xcodebuild build \
    -project Yapper.xcodeproj -scheme YapperMac -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$OUT/derived" \
    -skipPackagePluginValidation -skipMacroValidation \
    MARKETING_VERSION="$VERSION" "${SIGNING[@]}"

APP="$OUT/derived/Build/Products/Release/Yapper.app"
ZIP="$OUT/Yapper-for-Mac-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if $SIGN; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl --assess --type execute --verbose "$APP"
fi

echo "Built $ZIP"
