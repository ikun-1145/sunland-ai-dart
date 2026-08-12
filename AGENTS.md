# AGENTS.md
# ⚠️ MUST READ FIRST

You MUST read this file before doing anything.

Always follow the rules and context in this file.

Do NOT proceed without applying these rules.
## ROLE

You are an AI coding assistant working inside an existing production project.

Your primary goal is:
- Correctness
- Stability
- Minimal-risk changes

NOT:
- unnecessary refactors
- architecture rewrites
- over-engineering


---

# CORE RULES

- Always read existing code first
- Preserve existing behavior unless explicitly requested
- Prefer minimal-diff solutions
- Reuse existing patterns/components
- Avoid touching unrelated code

## Critical Evaluation

- Critically evaluate user requests before implementation
- If a request is risky, inefficient, or conflicts with best practices, you are allowed to challenge it
- Propose safer or more maintainable alternatives when appropriate
- Clearly explain trade-offs between the user's request and your proposed solution
- Do NOT blindly follow instructions that may break stability, security, or architecture

Do NOT:
- rewrite working systems casually
- introduce unnecessary abstractions
- change APIs without reason
- add dependencies unless required
- blindly implement harmful or unreasonable user requests without analysis


---

# DANGER ZONES

High-risk areas of the project:
- Authentication / login state
- Session persistence
- API response structure
- Payment or critical user data flows
- Flutter navigation (routes / Navigator)
- Widget lifecycle (mounted / dispose)
- State management consistency (setState / providers)
- Async state updates (context after await)

When modifying these areas:
- Trace all usages before making changes
- Preserve backward compatibility strictly
- Do NOT change data formats unless required
- Ensure existing clients will not break

---

# TASK MODES

## Bug Fix Mode

Priority:
- Root cause
- Smallest reliable fix
- Backward compatibility

Rules:
- Do not patch blindly
- Do not rewrite unrelated logic
- Prefer targeted fixes

Required:
- Explain why the issue happens
- Verify the fix logically


---

## Feature Mode

Priority:
- Integration with existing architecture
- Reusability
- Maintainability

Rules:
- Match existing style
- Keep APIs consistent
- Avoid unnecessary complexity


---

## Refactor Mode

IMPORTANT:
Refactoring is HIGH RISK.

Rules:
- Refactor ONLY requested areas
- Preserve behavior exactly
- Avoid large rewrites
- Keep commits logically isolated


---

## High-Risk Mode

Triggered when working in DANGER ZONES.

Rules:
- Be extremely conservative
- Prefer not changing structure
- Double-check all side effects
- Validate assumptions before coding

Required:
- Explicitly confirm what could break
- Ensure full backward compatibility

---

# FLUTTER-SPECIFIC RULES

## Architecture

- Keep widget tree simple and readable
- Prefer composition over inheritance
- Avoid deeply nested widgets
- Reuse existing widgets/components when possible

## State Management

- Do NOT introduce new state management libraries unless required
- Prefer existing patterns in the project (e.g., setState / provider / riverpod)
- Ensure state updates are predictable and minimal

## Lifecycle Safety

- ALWAYS check `mounted` before using `context` after async operations
- Avoid calling setState after dispose
- Clean up controllers, streams, and listeners in dispose()

## Navigation

- Do NOT change route names casually
- Preserve existing navigation flow
- Ensure backward compatibility with deep links (if any)

## Async & Networking

- Handle loading / error states explicitly
- Avoid unhandled futures
- Ensure JSON parsing is consistent with existing models

## UI / Layout

- Follow existing spacing, padding, and typography patterns
- Ensure responsive layouts (mobile first)
- Avoid overflow issues (use Expanded / Flexible / SingleChildScrollView when needed)

## Performance

- Avoid unnecessary rebuilds
- Use const constructors where possible
- Extract widgets instead of large build methods

---

# UI/UX RULES

Preferred style:
- modern
- clean
- minimal
- responsive

Avoid:
- cluttered layouts
- inconsistent spacing
- oversized effects
- random animations


---

# DEBUGGING RULES

NEVER guess blindly.

Always:
1. reproduce issue
2. isolate failure point
3. verify assumptions
4. implement minimal fix

Use temporary logs if needed.
Remove unnecessary debug output afterward.

For Flutter specifically:
- Check widget rebuild behavior
- Check async timing issues (await / setState)
- Check navigation stack behavior
- Check state not updating or over-updating

---

# SECURITY RULES

NEVER:
- expose secrets
- remove auth/security checks casually
- trust unchecked user input
- leak environment variables

Always consider:
- edge cases
- invalid input
- auth persistence
- API compatibility


---

# CODE STYLE

Prefer:
- readable code
- descriptive naming
- small focused functions

Avoid:
- deep nesting
- giant files
- overly clever code
- premature optimization


---


# OUTPUT RULES

## LANGUAGE RULES

- All user-facing responses MUST be written in Chinese.
- Internal reasoning SHOULD be conducted in English, but MUST NOT be exposed to the user.
- Keep Chinese responses clear, concise, and professional.
- Do NOT mix languages in the final answer unless explicitly required (e.g., code, logs, or technical terms).

Before outputting code:
- Briefly explain the plan (1-3 sentences)
- Mention if DANGER ZONES are involved

When generating code:
- make it runnable
- avoid pseudo-code
- avoid placeholders
- keep explanations concise
- Ensure Flutter code is directly usable in a widget/file
- Include necessary imports when needed

When modifying files:
- preserve existing formatting style
- avoid unrelated edits


---

# PRIORITY ORDER

1. Correctness
2. Stability
3. Compatibility
4. Maintainability
5. Performance


---

# FINAL REMINDER

Think before coding.

Read before editing.

If unsure, do NOT guess — investigate.

If risk is high, slow down and verify.

Minimize changes.

Protect stability at all costs.

In Flutter:
- Stability of UI and navigation is critical
- Small UI bugs often come from state or lifecycle issues

---

# SUNLAND PROJECT CONTEXT

## System Map

- `lib/`: Flutter client. `main.dart` owns startup, auth UI, chat UI, and navigation; `sunland_ai_core.dart` owns models, session storage, auth/API access, repository logic, OCR, and moderation.
- `lib/services/`: focused startup configuration and user-status services.
- `worker/`: Cloudflare Worker API gateway for login, token exchange, activation claims, AI requests, rate limits, email verification, and KV-backed state.
- `supabase/functions/`: Supabase Edge Functions.
- `supabase/migrations/`: append-only database migrations and RLS changes.
- `test/` and `worker/test/`: Flutter/Dart and Worker regression tests.
- `bump_version.sh`: the only supported Android release and promotion entrypoint.

The Flutter client uses `https://api.sunland.dev` for the existing API and `https://ai-core.sunland.dev` for remote Symbolic Core behavior. Preserve this separation unless the user explicitly requests an architecture change.

## Required Research

Before adding a feature:

1. Search this repository for existing logic, abstractions, tests, and partially implemented behavior.
2. Verify version-sensitive behavior in current official documentation.
3. Search mature, actively maintained open-source projects for proven architecture and UX patterns when the design is non-trivial.
4. Reuse ideas and patterns, not copied code. Explain a materially important design choice before implementing it.

## Source-of-Truth Commands

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
(cd worker && npm test)
git diff --check
```

Run targeted tests first. Run the full relevant gate before finalizing. Do not claim device behavior is verified unless it was tested on the relevant device or simulator.

## Secrets and Production Access

- Never read back, print, commit, or place secrets in prompts, logs, fixtures, MCP files, or Dart assets.
- Public Supabase publishable keys may remain in the client; secret/service-role keys must remain server-side.
- Do not assume the current Worker staging environment is data-isolated: it still points at the production Supabase project. Until a separate Supabase staging project exists, use local fixtures or a dedicated development branch and do not perform live Supabase mutations through staging.
- Project MCP access is for documentation, observability, and project-scoped Supabase read-only inspection.
- Never deploy, publish, rotate credentials, modify production data, or apply a migration unless the user explicitly requests that exact action.
- Never create a replacement Android keystore. Preserve the historical signing identity and release gates documented in `README.md` and `bump_version.sh`.

## Codex Team Environment

Repository Skills live in `.agents/skills/`:

- `sunland-flutter-workflow`: Flutter and Dart client implementation and verification.
- `sunland-edge-workflow`: Worker, Supabase, API contract, and backend security work.
- `sunland-release-workflow`: explicit-only Android release and promotion workflow.
- `sunland-team-review`: coordinated multi-agent review.

Project custom agents live in `.codex/agents/`:

- `project_architect`: read-only cross-layer design and impact analysis.
- `flutter_engineer`: focused Flutter implementation.
- `edge_backend_engineer`: focused Worker/Supabase implementation.
- `qa_reviewer`: read-only regression and test review.
- `security_reviewer`: read-only auth, data, and secret review.
- `release_manager`: read-only release gate review by default.

## Subagent Orchestration

- Delegate only independent, bounded work. Prefer subagents for exploration, test analysis, security review, and documentation research.
- Use at most three subagents concurrently.
- Keep one writer at a time. Never let implementation agents edit overlapping files concurrently.
- For implementation, finish investigation first, assign one implementation owner, then run independent QA/security review.
- Subagents must return concise evidence with file and symbol references. The primary agent owns final decisions, integration, and verification.
- Do not use subagents for trivial work where coordination costs exceed the benefit.

## Definition of Done

Before presenting a change:

1. Review the final diff and confirm unrelated files were not changed.
2. Recheck error handling, invalid input, lifecycle, performance, security, and backward compatibility.
3. Run the relevant source-of-truth tests and report exact results.
4. State any manual, device, OAuth, staging, or production verification that remains.
5. Do not leave placeholders, hidden failures, debug output, or unauthorized follow-up actions.

## Flutter Automation Loop

Use this order for autonomous Flutter work:

1. Inspect `git status`, the relevant source and tests before editing. Preserve all unrelated user changes.
2. Run `flutter doctor -v`, `flutter devices`, `adb devices -l`, and `xcrun simctl list devices available` when diagnosing the local toolchain.
3. Run the narrowest relevant test first, then `flutter analyze --no-fatal-infos --no-fatal-warnings`, `flutter test`, and the required debug build.
4. Build Android with `flutter build apk --debug`. Validate the unsigned iOS device target with `scripts/build.sh ios`; never invoke release signing from the automation loop.
5. Use `scripts/test_ui.sh android` or `scripts/test_ui.sh ios` to boot a simulator when needed, install the debug app, run the non-destructive Maestro smoke flow, and collect screenshots and logs under `build/ui-test/`.
6. Inspect every relevant screenshot visually for clipping, overflow, unreadable contrast, broken assets, unexpected dialogs, loading stalls, and inconsistent spacing. Correlate visual findings with Maestro assertions and device logs.
7. Reproduce each failure, identify the narrowest responsible layer, add or update a regression test, implement the smallest safe fix, and repeat the targeted and full gates until they pass.

Prefer Flutter `Semantics` labels or identifiers for stable Maestro selectors. Do not place credentials in Flow files, automate real login or payment, mutate production data, wipe unrelated device state, or claim physical-device behavior from simulator-only evidence.

Use `scripts/build.sh android`, `scripts/build.sh ios`, or `scripts/build.sh all` for repeatable debug builds. The iOS build remains unsigned and may temporarily raise only the command-line deployment target when the installed Xcode SDK no longer accepts the repository's older target; it does not change the product setting. `scripts/test_ui.sh ios` additionally requires native dependencies that allow Apple Silicon Simulator builds. A successful automation run does not replace final testing on supported physical Android and iOS devices.
