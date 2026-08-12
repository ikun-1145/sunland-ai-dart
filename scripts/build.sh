#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly TARGET="${1:-all}"

resolve_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return
  fi

  local candidate
  for candidate in \
    "${FLUTTER_ROOT:-}/bin/flutter" \
    "/Users/liuxize/development/flutter/bin/flutter"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf 'Flutter CLI not found. Configure PATH or FLUTTER_ROOT first.\n' >&2
  return 1
}

usage() {
  printf 'Usage: %s [android|ios|all]\n' "$0" >&2
}

version_is_less_than() {
  local lhs="$1"
  local rhs="$2"
  awk -v lhs="$lhs" -v rhs="$rhs" 'BEGIN {
    split(lhs, left, ".")
    split(rhs, right, ".")
    for (part = 1; part <= 3; part++) {
      left_part = (part in left) ? left[part] + 0 : 0
      right_part = (part in right) ? right[part] + 0 : 0
      if (left_part < right_part) exit 0
      if (left_part > right_part) exit 1
    }
    exit 1
  }'
}

build_ios_device() {
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
    printf 'Unsigned iOS builds require macOS and Xcode.\n' >&2
    return 69
  fi

  if [[ ! -f ios/Runner.xcworkspace/contents.xcworkspacedata ]]; then
    printf 'iOS workspace is missing. Run CocoaPods setup first.\n' >&2
    return 69
  fi

  if [[ ! -f ios/Pods/Manifest.lock ]] || ! cmp -s ios/Podfile.lock ios/Pods/Manifest.lock; then
    if ! command -v pod >/dev/null 2>&1; then
      printf 'CocoaPods sandbox is missing or stale, and pod is unavailable.\n' >&2
      return 69
    fi
    (cd ios && pod install --deployment)
  fi

  local project_target
  local sdk_settings
  local sdk_minimum_target
  local effective_target=""
  local -a xcode_arguments

  project_target="$(awk -F '= ' '/IPHONEOS_DEPLOYMENT_TARGET =/ {
    value = $2
    gsub(/[;[:space:]]/, "", value)
    print value
    exit
  }' ios/Runner.xcodeproj/project.pbxproj)"
  sdk_settings="$(xcrun --sdk iphoneos --show-sdk-path)/SDKSettings.plist"
  sdk_minimum_target="$(/usr/libexec/PlistBuddy \
    -c 'Print :SupportedTargets:iphoneos:MinimumDeploymentTarget' \
    "$sdk_settings")"

  if [[ -n "${IOS_AUTOMATION_DEPLOYMENT_TARGET:-}" ]]; then
    effective_target="$IOS_AUTOMATION_DEPLOYMENT_TARGET"
  elif [[ -n "$project_target" ]] && \
      version_is_less_than "$project_target" "$sdk_minimum_target"; then
    effective_target="$sdk_minimum_target"
  fi

  xcode_arguments=(
    -workspace ios/Runner.xcworkspace
    -scheme Runner
    -configuration Debug
    -sdk iphoneos
    -destination generic/platform=iOS
    -derivedDataPath build/ios-device
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )

  if [[ -n "$effective_target" ]]; then
    printf 'Using temporary iOS deployment target %s for this Xcode SDK.\n' \
      "$effective_target"
    xcode_arguments+=("IPHONEOS_DEPLOYMENT_TARGET=$effective_target")
  fi

  xcodebuild "${xcode_arguments[@]}" build
  printf 'Unsigned iOS debug app: %s\n' \
    "$PROJECT_ROOT/build/ios-device/Build/Products/Debug-iphoneos/Runner.app"
}

case "$TARGET" in
  android | ios | all) ;;
  *)
    usage
    exit 64
    ;;
esac

readonly FLUTTER_BIN="$(resolve_flutter)"

cd "$PROJECT_ROOT"
"$FLUTTER_BIN" pub get

if [[ "$TARGET" == "android" || "$TARGET" == "all" ]]; then
  "$FLUTTER_BIN" build apk --debug
  printf 'Android debug APK: %s\n' \
    "$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
fi

if [[ "$TARGET" == "ios" || "$TARGET" == "all" ]]; then
  build_ios_device
fi
