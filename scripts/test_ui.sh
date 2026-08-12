#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PLATFORM="${1:-android}"
readonly ANDROID_SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/Users/liuxize/Library/Android/sdk}}"
readonly RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
readonly OUTPUT_DIR="build/ui-test/${PLATFORM}-${RUN_STAMP}"
readonly OUTPUT_ABS="$PROJECT_ROOT/$OUTPUT_DIR"

resolve_tool() {
  local name="$1"
  shift
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf '%s not found. Configure the development environment first.\n' "$name" >&2
  return 1
}

wait_for_android() {
  local adb_bin="$1"
  local serial="$2"
  local attempt
  for attempt in {1..120}; do
    if [[ "$($adb_bin -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      "$adb_bin" -s "$serial" shell input keyevent 82 >/dev/null 2>&1 || true
      return
    fi
    sleep 2
  done
  printf 'Android emulator %s did not finish booting.\n' "$serial" >&2
  return 1
}

select_ios_simulator() {
  xcrun simctl list devices available | awk -F '[()]' '
    /iPhone/ && /Booted/ { print $2; exit }
    /iPhone/ && first == "" { first = $2 }
    END { if (first != "") print first }
  ' | head -n 1
}

capture_fallback_screenshot() {
  local status=$?
  mkdir -p "$OUTPUT_ABS"
  if [[ "$PLATFORM" == "android" && -n "${ANDROID_SERIAL_FOR_TEST:-}" ]]; then
    "$ADB_BIN" -s "$ANDROID_SERIAL_FOR_TEST" exec-out screencap -p \
      >"$OUTPUT_ABS/final-device-screen.png" 2>/dev/null || true
  elif [[ "$PLATFORM" == "ios" && -n "${IOS_SIMULATOR_FOR_TEST:-}" ]]; then
    xcrun simctl io "$IOS_SIMULATOR_FOR_TEST" screenshot \
      "$OUTPUT_ABS/final-device-screen.png" >/dev/null 2>&1 || true
  fi
  if (( status != 0 )); then
    printf 'UI test failed. Inspect artifacts in %s\n' "$OUTPUT_ABS" >&2
  fi
  return "$status"
}

case "$PLATFORM" in
  android | ios) ;;
  *)
    printf 'Usage: %s [android|ios]\n' "$0" >&2
    exit 64
    ;;
esac

readonly MAESTRO_BIN="$(resolve_tool maestro /Users/liuxize/.maestro/bin/maestro)"
readonly FLUTTER_BIN="$(resolve_tool flutter /Users/liuxize/development/flutter/bin/flutter)"
mkdir -p "$OUTPUT_ABS"
cd "$PROJECT_ROOT"
trap capture_fallback_screenshot EXIT

if [[ "$PLATFORM" == "android" ]]; then
  readonly ADB_BIN="$(resolve_tool adb "$ANDROID_SDK_DIR/platform-tools/adb")"
  readonly EMULATOR_BIN="$(resolve_tool emulator "$ANDROID_SDK_DIR/emulator/emulator")"
  ANDROID_SERIAL_FOR_TEST="${UI_DEVICE_ID:-$($ADB_BIN devices | awk '$2 == "device" && $1 ~ /^emulator-/ { print $1; exit }')}"

  if [[ -z "$ANDROID_SERIAL_FOR_TEST" ]]; then
    readonly AVD_NAME="${ANDROID_AVD:-$($EMULATOR_BIN -list-avds | head -n 1)}"
    if [[ -z "$AVD_NAME" ]]; then
      printf 'No Android AVD is installed. Create one with avdmanager first.\n' >&2
      exit 69
    fi
    "$EMULATOR_BIN" @"$AVD_NAME" -no-snapshot-save \
      >"$OUTPUT_ABS/emulator.log" 2>&1 &
    readonly EMULATOR_PID=$!
    for _ in {1..60}; do
      ANDROID_SERIAL_FOR_TEST="$($ADB_BIN devices | awk '$2 == "device" && $1 ~ /^emulator-/ { print $1; exit }')"
      [[ -n "$ANDROID_SERIAL_FOR_TEST" ]] && break
      if ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
        printf 'Android emulator exited during startup:\n' >&2
        tail -n 40 "$OUTPUT_ABS/emulator.log" >&2 || true
        exit 1
      fi
      sleep 2
    done
  fi

  if [[ -z "$ANDROID_SERIAL_FOR_TEST" ]]; then
    printf 'Android emulator did not appear in adb.\n' >&2
    exit 1
  fi
  export ANDROID_SERIAL_FOR_TEST
  wait_for_android "$ADB_BIN" "$ANDROID_SERIAL_FOR_TEST"
  "$SCRIPT_DIR/build.sh" android
  "$ADB_BIN" -s "$ANDROID_SERIAL_FOR_TEST" install -r \
    "$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  "$MAESTRO_BIN" --device "$ANDROID_SERIAL_FOR_TEST" test \
    "$PROJECT_ROOT/.maestro/smoke-android.yaml" \
    --test-output-dir "$OUTPUT_ABS"
else
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcrun >/dev/null 2>&1; then
    printf 'iOS UI tests require macOS, Xcode, and an iOS Simulator runtime.\n' >&2
    exit 69
  fi
  IOS_SIMULATOR_FOR_TEST="${UI_DEVICE_ID:-$(select_ios_simulator)}"
  if [[ -z "$IOS_SIMULATOR_FOR_TEST" ]]; then
    printf 'No available iPhone Simulator was found.\n' >&2
    exit 69
  fi
  export IOS_SIMULATOR_FOR_TEST
  xcrun simctl boot "$IOS_SIMULATOR_FOR_TEST" >/dev/null 2>&1 || true
  open -a Simulator --args -CurrentDeviceUDID "$IOS_SIMULATOR_FOR_TEST" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$IOS_SIMULATOR_FOR_TEST" -b
  readonly PODS_RUNNER_XCCONFIG="$PROJECT_ROOT/ios/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"
  if [[ "$(uname -m)" == "arm64" ]] && \
      [[ -f "$PODS_RUNNER_XCCONFIG" ]] && \
      grep -Eq '^EXCLUDED_ARCHS\[sdk=iphonesimulator\*\].*arm64' "$PODS_RUNNER_XCCONFIG"; then
    printf '%s\n' \
      'The locked iOS native dependencies exclude arm64 Simulator builds.' \
      'The Simulator was booted, but this app cannot run on Apple Silicon until those dependencies are upgraded.' \
      'Use scripts/build.sh ios to verify the unsigned iOS device target in the meantime.' >&2
    exit 78
  fi
  "$FLUTTER_BIN" build ios --simulator --debug
  xcrun simctl install "$IOS_SIMULATOR_FOR_TEST" \
    "$PROJECT_ROOT/build/ios/iphonesimulator/Runner.app"
  "$MAESTRO_BIN" --device "$IOS_SIMULATOR_FOR_TEST" test \
    "$PROJECT_ROOT/.maestro/smoke-ios.yaml" \
    --test-output-dir "$OUTPUT_ABS"
fi

printf 'UI test artifacts: %s\n' "$OUTPUT_ABS"
