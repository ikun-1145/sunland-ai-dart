---
name: sunland-release-workflow
description: Prepare, validate, publish, or promote a Sunland Android release with bump_version.sh. Use only when the user explicitly asks for a release, version bump, release dry-run, APK signing verification, GitHub Release publication, mainland-download promotion, or update.json rollout.
---

# Sunland Release Workflow

Treat release work as a gated production operation. Never infer authorization to commit, push, publish, promote, or change RLS state.

## Establish the requested stage

Choose exactly one stage:

1. **Inspect**: read version, prerequisites, worktree state, and release history without changes.
2. **Dry-run**: run the script's limited non-mutating checks, then report which publication prerequisites were not covered.
3. **Publish**: build, verify the historical signing certificate, commit, push, and create a GitHub Release.
4. **Promote**: update the website only after independent mainland APK download verification.

If the user has not explicitly authorized the requested mutating stage, stop after inspection or dry-run.

## Preserve release invariants

- Read `README.md` and the complete `bump_version.sh` before acting.
- Require a clean worktree for publication and promotion.
- Require version format `X.Y.Z+N`.
- Confirm the target is strictly newer than `pubspec.yaml` and that neither the Git tag nor GitHub Release already exists.
- Never create or substitute a keystore, alias, password, reference APK, or signing identity.
- Do not reveal signing paths or credentials in output.
- Do not bypass Flutter analysis, tests, release build, checksum generation, or certificate comparison.
- Do not promote before the release assets exist and the mainland download is independently confirmed.
- Do not apply deferred RLS enforcement until the forced-update behavior has been verified.

## Compensate for current script limitations

- Do not treat `--dry-run` as a complete release preflight: it currently checks Flutter availability and `git diff --check`, but not worktree cleanliness, target monotonicity, existing tags/releases, GitHub auth, signing tools, or release inputs.
- Inspect the generated checksum before upload and require it to reference the APK basename so it can be verified beside the downloaded asset.
- The publish and promote paths are not guaranteed to be idempotent after a partial commit, push, or GitHub failure. Never rerun blindly; inspect local HEAD, remote branch, tag, Release assets, and website state, then propose an explicit recovery plan.

## Use the repository entrypoint

Dry-run only:

```bash
./bump_version.sh --target X.Y.Z+N --dry-run
```

Publish only with explicit authorization and real local paths:

```bash
./bump_version.sh \
  --target X.Y.Z+N \
  --reference-apk /absolute/path/to/reference.apk \
  --notes-file /absolute/path/to/release-notes.md
```

Promote only with explicit authorization after independent verification:

```bash
./bump_version.sh \
  --target X.Y.Z+N \
  --promote \
  --website-repo /absolute/path/to/website \
  --confirm-mainland-download
```

Report which stage completed, which irreversible actions occurred, which script limitations were checked, and which gates remain.
