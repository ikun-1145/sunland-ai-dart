---
name: sunland-flutter-workflow
description: Implement, debug, review, or test Sunland Flutter and Dart client changes. Use when a task touches lib/, test/, pubspec.yaml, platform integration, widgets, navigation, lifecycle, sessions, authentication, AI chat, OCR, updates, or other mobile-client behavior in this repository.
---

# Sunland Flutter Workflow

Apply the smallest production-safe Flutter change that satisfies the request while preserving authentication, session, API, and navigation behavior.

## Inspect before editing

1. Read `AGENTS.md`, `README.md`, `pubspec.yaml`, and the relevant tests.
2. Locate symbols with `rg`; do not scan or rewrite the full `lib/main.dart` or `lib/sunland_ai_core.dart` when a focused read is enough.
3. Trace callers, state ownership, async boundaries, persistence, and API serialization before changing behavior.
4. Check the current codebase for an existing widget, service, helper, or test pattern before adding one.
5. For version-sensitive Flutter APIs, verify current official documentation or a maintained primary source.

## Respect project boundaries

- Treat auth, token refresh, session persistence, API response parsing, navigation, widget lifecycle, update enforcement, and payment-related UI as high risk.
- Preserve endpoint URLs, JSON formats, stored keys, route behavior, and backward compatibility unless the user explicitly requests a contract change.
- Check `mounted` after every relevant async gap, including success, `catch`, and `finally` paths, before using `context`, controllers, or `setState`.
- When a notifier or navigation call can remove the current widget, confirm the single navigation owner and stop using widget-owned state after that transition.
- Dispose controllers, streams, timers, subscriptions, and listeners owned by a widget.
- Reuse the current `setState` and service patterns; do not introduce a state-management package without explicit approval.
- Never move a server secret into Dart, assets, build arguments, logs, or committed configuration.

## Implement one focused change

1. Reproduce or characterize the requested behavior.
2. Identify the narrowest responsible layer: widget, service, model, storage, or API client.
3. Add or update a regression test before or with the fix. Require one for auth, navigation, session, and lifecycle bugs; if automation is genuinely impractical, explain why and define a manual reproduction check.
4. Keep unrelated formatting and refactors out of the diff.
5. Re-read the changed async and lifecycle paths for disposal, retries, duplicate requests, and stale state.

## Verify proportionally

Select the existing test file that covers the changed path and run it first; for example, a token-lifecycle change can start with:

```bash
flutter test test/database_token_provider_test.dart
```

Then run the standard client gate when the change is ready:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
git diff --check
```

Report any device-only behavior that still needs manual verification. If a non-code task does not justify the full client gate, state exactly which commands were intentionally omitted and why.

Do not deploy, publish, alter a database, rotate credentials, or run the release script from this workflow.
