---
name: sunland-edge-workflow
description: Implement, debug, review, or test Sunland backend changes across worker/, supabase/functions/, supabase/migrations/, and Flutter-to-backend API contracts. Use for Cloudflare Workers, KV, secrets, authentication endpoints, Supabase Auth or RLS, Edge Functions, database access, API errors, rate limits, and server-side security work in this repository.
---

# Sunland Edge Workflow

Maintain the Cloudflare Worker and Supabase layers without widening production access or breaking the Flutter client contract.

## Classify the change

1. Read `AGENTS.md`, `README.md`, `worker/wrangler.jsonc`, and the affected source and tests.
2. Decide whether the owner is the Worker, a Supabase Edge Function, a migration, or the Flutter client contract.
3. Trace both sides of every request or response change. Preserve existing status codes, JSON keys, token semantics, and compatibility unless a breaking change is explicitly authorized.
4. Use the installed Cloudflare or Supabase platform skill when available, and verify version-sensitive behavior against current official documentation.

## Apply security boundaries

- Treat authentication, JWT validation, activation claims, rate limits, KV state, user data, RLS, functions, and secrets as high risk.
- Never print, read back, commit, or place secrets in commands, patches, fixtures, MCP configuration, or documentation.
- Keep `APP_JWT_*`, `SUPABASE_SECRET_KEY`, `DEEPSEEK_API_KEY`, `GEETEST_SERVER_KEY`, and `RESEND_API_TOKEN` in Cloudflare Secret storage.
- Keep the Supabase MCP project-scoped and read-only for inspection. Do not use MCP to mutate production schema or data.
- Do not treat Worker staging as a safe database sandbox: the current staging configuration points at the production Supabase project. Use local fixtures or a separately isolated Supabase development branch for live mutations.
- Do not change a database schema, auth model, permissions, RLS policy, or production binding without explicit confirmation.
- Do not deploy a Worker or Edge Function unless the user explicitly requests deployment after review.

## Implement safely

1. Reproduce the failing request or define the new contract with concrete inputs, outputs, and error cases.
2. Reuse existing response helpers, JWT helpers, configuration fallbacks, and test fixtures.
3. Validate input types, size, authorization, origin, failure responses, and retry or idempotency behavior.
4. For a migration, create a new append-only migration through the Supabase CLI; never edit an applied migration. Include explicit grants and RLS where Data API access is intended.
5. Keep one writer responsible for the backend diff. Use other agents for read-only research or review.

## Verify proportionally

For Worker changes:

```bash
cd worker
npm test
```

For Flutter-visible contracts, also run the relevant Dart test and the normal Flutter gate. For SQL or RLS work, review the generated migration, run relevant repository migration tests, and use a separately isolated development branch or local Supabase environment for live verification.

Do not report a production fix as verified when only static or mocked tests ran.
