---
name: sunland-team-review
description: Orchestrate a production-grade Sunland code, architecture, security, or release review with specialized subagents. Use when the user asks for a full review, team review, parallel review, multi-agent audit, pre-release assessment, cross-layer investigation, or coordinated review of Flutter, Worker, Supabase, security, and tests.
---

# Sunland Team Review

Use specialized subagents to gather independent evidence, then consolidate findings in the primary thread. Keep review work read-only.

## Select roles by scope

- Use `project_architect` to map cross-layer execution paths and compatibility risks.
- Use `qa_reviewer` to inspect regression coverage, commands, failure paths, and test gaps.
- Use `security_reviewer` for auth, session, secrets, JWT, API, RLS, storage, or user-data exposure.
- Use `release_manager` for versioning, signing, publication, promotion, and rollback readiness.
- Use `flutter_engineer` or `edge_backend_engineer` only when the user also authorized implementation.

Do not spawn every role automatically. Select the smallest set that covers independent review questions.

## Orchestrate safely

1. Define one bounded question and expected evidence for each subagent.
2. Run at most three subagents concurrently.
3. Prefer parallel read-heavy exploration, tests, and review.
4. Never allow two implementation agents to edit overlapping files at the same time. Keep one active writer.
5. Wait for all requested roles, then verify their claims against the actual diff or source before accepting them.
6. Resolve conflicting conclusions in the primary thread; do not average them together.

## Return an owner-level review

Lead with actionable findings ordered by severity. For each finding include:

- affected file and tight location;
- concrete failure mode or security impact;
- reproduction or evidence;
- smallest safe remediation;
- missing verification, if any.

Separate confirmed findings from open questions. If no material issue is found, state that clearly and list the remaining test or environment gaps.
