#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET=""
WEBSITE_REPO=""
REFERENCE_APK=""
NOTES_FILE=""
DRY_RUN=false
PROMOTE=false
CONFIRM_MAINLAND_DOWNLOAD=false

usage() {
  echo "Usage: $0 --target X.Y.Z+N [--dry-run | --promote --website-repo PATH --confirm-mainland-download | --reference-apk PATH --notes-file PATH]"
}

while (($#)); do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --website-repo) WEBSITE_REPO="${2:-}"; shift 2 ;;
    --reference-apk) REFERENCE_APK="${2:-}"; shift 2 ;;
    --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --promote) PROMOTE=true; shift ;;
    --confirm-mainland-download) CONFIRM_MAINLAND_DOWNLOAD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "--target must use X.Y.Z+N format" >&2
  exit 2
fi

cd "$SCRIPT_DIR"
CURRENT="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
if [[ -z "$CURRENT" ]]; then
  echo "pubspec.yaml has no version field" >&2
  exit 1
fi

TARGET_NAME="${TARGET%%+*}"
TARGET_BUILD="${TARGET##*+}"
TAG="v$TARGET"
APK_SOURCE="build/app/outputs/flutter-apk/app-release.apk"
APK_RELEASE="build/app/outputs/flutter-apk/sunland-ai-$TARGET.apk"
CHECKSUM="$APK_RELEASE.sha256"

echo "Release validation: $CURRENT -> $TARGET"
command -v flutter >/dev/null || { echo "flutter is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

if [[ "$DRY_RUN" == true ]]; then
  flutter --no-version-check --version
  git diff --check
  echo "Dry-run passed. No version, release, tag, update.json, or RLS state was changed."
  exit 0
fi

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
gh auth status -h github.com >/dev/null

if [[ "$PROMOTE" == true ]]; then
  if [[ "$CONFIRM_MAINLAND_DOWNLOAD" != true ]]; then
    echo "--confirm-mainland-download is required after independent mainland download verification" >&2
    exit 2
  fi
  if [[ -z "$WEBSITE_REPO" || ! -f "$WEBSITE_REPO/update.json" ]]; then
    echo "--website-repo must point to the website repository" >&2
    exit 2
  fi
  if [[ -n "$(git -C "$WEBSITE_REPO" status --porcelain)" ]]; then
    echo "Website worktree must be clean before promotion" >&2
    exit 1
  fi
  gh release view "$TAG" --json assets --jq '.assets[].name' | grep -Fx "sunland-ai-$TARGET.apk" >/dev/null
  gh release view "$TAG" --json assets --jq '.assets[].name' | grep -Fx "sunland-ai-$TARGET.apk.sha256" >/dev/null

  TARGET_NAME="$TARGET_NAME" TARGET_BUILD="$TARGET_BUILD" TAG="$TAG" \
    node -e '
      const fs = require("fs");
      const path = process.argv[1];
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      data.version = process.env.TARGET_NAME;
      data.build = Number(process.env.TARGET_BUILD);
      data.url = `https://github.com/ikun-1145/sunland-ai-dart/releases/download/${encodeURIComponent(process.env.TAG)}/sunland-ai-${process.env.TARGET_NAME}%2B${process.env.TARGET_BUILD}.apk`;
      data.force = true;
      fs.writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);
    ' "$WEBSITE_REPO/update.json"

  git -C "$WEBSITE_REPO" add update.json
  git -C "$WEBSITE_REPO" commit -m "chore: force update to $TARGET"
  git -C "$WEBSITE_REPO" push
  echo "Promoted $TARGET. Verify the old app cannot bypass the update before applying deferred RLS enforcement."
  exit 0
fi

if [[ -z "$REFERENCE_APK" || ! -f "$REFERENCE_APK" ]]; then
  echo "--reference-apk must point to the installable v1.2.1+27 APK" >&2
  exit 2
fi
if [[ -z "$NOTES_FILE" || ! -f "$NOTES_FILE" ]]; then
  echo "--notes-file is required" >&2
  exit 2
fi
if [[ ! -f android/key.properties ]]; then
  echo "android/key.properties is missing; never create a replacement keystore" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Flutter worktree must be clean before a release" >&2
  exit 1
fi
perl -0pi -e "s/^version:\s*.*$/version: $TARGET/m" pubspec.yaml

flutter --no-version-check pub get
flutter --no-version-check analyze --no-fatal-infos --no-fatal-warnings
flutter --no-version-check test
flutter --no-version-check build apk --release
cp "$APK_SOURCE" "$APK_RELEASE"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
APKSIGNER="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -n 1)"
if [[ -z "$APKSIGNER" ]]; then
  echo "Android apksigner is required" >&2
  exit 1
fi
REFERENCE_CERT="$($APKSIGNER verify --print-certs "$REFERENCE_APK" | awk -F': ' '/certificate SHA-256 digest:/{print $NF; exit}')"
RELEASE_CERT="$($APKSIGNER verify --print-certs "$APK_RELEASE" | awk -F': ' '/certificate SHA-256 digest:/{print $NF; exit}')"
if [[ -z "$REFERENCE_CERT" || "$REFERENCE_CERT" != "$RELEASE_CERT" ]]; then
  echo "APK signing certificate does not match v1.2.1+27" >&2
  exit 1
fi
(cd "$(dirname "$APK_RELEASE")" && shasum -a 256 "$(basename "$APK_RELEASE")") > "$CHECKSUM"

# Nothing is pushed until tests, release build, and historical-signature
# verification have all succeeded.
git add pubspec.yaml pubspec.lock bump_version.sh
git commit -m "chore: release $TARGET"
git push
gh release create "$TAG" "$APK_RELEASE" "$CHECKSUM" \
  --target "$(git rev-parse HEAD)" --title "$TAG" --notes-file "$NOTES_FILE"

echo "Published $TARGET without forcing an update. Verify the APK download from mainland, then run:"
echo "  $0 --target $TARGET --promote --website-repo PATH --confirm-mainland-download"
