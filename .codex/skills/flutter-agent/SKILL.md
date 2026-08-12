---
name: flutter-agent
description: Build, run, drive, inspect, debug, and repeatedly verify Flutter mobile applications on Android emulators and iOS simulators. Use when Codex needs to check a Flutter toolchain, compile debug apps, boot devices, run Maestro UI flows, capture or analyze screenshots, discover UI regressions, fix Flutter or Dart bugs, or repeat tests until the client gates pass.
---

# Flutter Agent

Follow the repository `AGENTS.md` first. Use the smallest safe feedback loop from static analysis through real-device-surface UI inspection, and preserve unrelated working-tree changes.

## Inspect the environment

1. Read `README.md`, `pubspec.yaml`, relevant source and tests, then run `git status --short --branch`.
2. Check `flutter doctor -v`, `dart --version`, `flutter devices`, `adb devices -l`, `xcodebuild -version`, and `xcrun simctl list devices available`.
3. Resolve tools from `PATH`. On this workstation, the configured fallbacks are `/Users/liuxize/development/flutter`, `/Users/liuxize/Library/Android/sdk`, and the Android Studio bundled JDK.
4. Install only genuinely missing prerequisites. Never replace an existing SDK, Xcode installation, Android keystore, or project signing identity.
5. Verify every installation with its version command. For Maestro, require Java 17 or newer and confirm `maestro --version`.

## Reproduce before editing

Run the narrowest existing Dart test first. Trace widget state, async gaps, lifecycle, navigation, persistence, and API boundaries before changing code. Treat authentication, sessions, navigation, production endpoints, and user data as high risk.

Use `scripts/test_ui.sh android` or `scripts/test_ui.sh ios` for a repeatable black-box reproduction. The script builds and installs a debug app, starts a simulator when necessary, runs the platform Maestro smoke Flow, and stores artifacts in `build/ui-test/`.

## Inspect the UI

1. Inspect the current semantics hierarchy before selecting controls. Prefer `Semantics.identifier`, semantic labels, and visible text; Flutter `Key` values are not exposed to Maestro.
2. Capture screenshots before and after the affected interaction and on failures.
3. Open screenshots with the local image viewer. Check overflow, clipping, asset failures, contrast, touch-target sizing, alignment, spacing, keyboard overlap, loading stalls, unexpected dialogs, and platform differences.
4. Correlate visual findings with Maestro assertions, Flutter logs, and platform logs. Never infer a code bug from pixels alone.
5. Keep Flow files free of credentials and personal data. Do not automate real login, payment, activation claims, or production mutations.

## Fix and repeat

1. Add or update a regression test with the fix when practical.
2. Make the smallest focused change and preserve endpoint, storage, navigation, and JSON contracts.
3. Re-run the targeted test, then the UI Flow that reproduced the issue.
4. Run the full client gate:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
git diff --check
```

Use `scripts/build.sh ios` for an unsigned iOS device-target debug build when iOS compilation is in scope. The script may temporarily raise only the command-line deployment target to the installed Xcode SDK minimum; it must not change the repository's product target. Use `scripts/test_ui.sh ios` only when native dependencies allow Apple Silicon Simulator builds. Repeat until the targeted failure and relevant gates pass. Report exact commands, results, artifact paths, and any physical-device behavior that remains unverified.

## Simulator safety

- Use existing AVDs and simulators before creating new ones.
- Do not pass `-wipe-data` or erase a simulator unless the user explicitly requests it.
- Clear only the tested app's local state when a Flow requires a deterministic first launch.
- Keep iOS device-target builds in Debug with signing disabled; do not sign, archive, deploy, publish, or invoke `bump_version.sh`.
