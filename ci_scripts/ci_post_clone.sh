#!/bin/zsh
# Xcode Cloud post-clone hook for Yapper.
#
# Runs on Apple's build machine after the clone and before Xcode Cloud opens
# Yapper.xcodeproj. The project file is gitignored and generated from
# project.yml, so it is produced here. This directory has to sit next to the
# .xcodeproj.
set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

XCODEGEN_VERSION="2.46.0"
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! brew install xcodegen; then
    echo "brew install failed, using the pinned XcodeGen ${XCODEGEN_VERSION} release"
    curl -fsSL -o /tmp/xcodegen.zip \
      "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
    unzip -q -o /tmp/xcodegen.zip -d /tmp
    export PATH="/tmp/xcodegen/bin:$PATH"
  fi
fi

# project.yml takes the signing team from the environment. Xcode Cloud exposes
# the owning team as CI_TEAM_ID.
if [[ -z "${CI_TEAM_ID:-}" ]]; then
  echo "CI_TEAM_ID is not set; cannot choose a signing team" >&2
  exit 1
fi
export DEVELOPMENT_TEAM="$CI_TEAM_ID"
echo "signing team taken from CI_TEAM_ID (${#CI_TEAM_ID} characters)"

xcodegen --version
xcodegen generate --spec project.yml

# Version string: newest v* tag reachable from this commit (v0.2.0 -> 0.2.0).
# Xcode Cloud sets CFBundleVersion itself at archive time, so only the
# marketing version is stamped here, into the app and both extensions (App
# Store Connect wants them to match). Xcode Cloud clones shallow and without
# tags, so fetch history + tags first; with no tag the project.yml value stays.
if ! git fetch --quiet --tags --unshallow origin 2>/dev/null; then
  git fetch --quiet --tags origin || echo "could not fetch tags from origin"
fi
TAG="$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)"
if [[ -n "$TAG" ]]; then
  for plist in Yapper/Info.plist YapperKeyboard/Info.plist YapperWidgets/Info.plist; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${TAG#v}" "$plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${TAG#v}" "$plist"
  done
  echo "CFBundleShortVersionString set to ${TAG#v} from tag ${TAG}"
else
  echo "no v* tag reachable; keeping the version from project.yml"
fi

# Xcode Cloud builds with automatic package resolution turned off, so the
# generated project needs the committed Package.resolved in place. GitHub CI
# checks that the committed file matches what Xcode resolves.
RESOLVED_DIR="Yapper.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED_DIR"
cp Package.resolved "$RESOLVED_DIR/Package.resolved"
