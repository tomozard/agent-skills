# Verifier assignment — copy this shape

The bounded verifier dispatch referenced by `references/communication-protocol.md`.
Both blocks are mandatory; the changed-file list comes from the frozen candidate
artifact's `diff --git` lines, never from `Allowed files` and never from memory.

```text
[TASK] from: pm-ap_intranet -> to: reviewer-ap_intranet
Verify the frozen candidate for task pm-ap_intranet-ci-014.
Controller session: {pm session}
Reply required: [ACK], then one verdict ([PASS] or [CHANGES_REQUIRED]), to session {pm session}

Operation: implementation (review only — READ-ONLY)
Base branch: dev
Work branch: fix/ci-014-timeout
Allowed files (4): .gitlab-ci.yml, ci/templates/test.yml, ci/templates/build.yml, docs/ci.md
Candidate artifact: /Users/arsan_t/Workspaces/.agents/candidates/task-pm-ap_intranet-ci-014.md
Candidate Diff SHA-256: {sha256}
Required behavior: R1 the test stage times out at 30 minutes; R2 build keeps 60 minutes.

Acceptance Gate
B1 R1 — test job in .gitlab-ci.yml declares timeout: 30m and the rendered pipeline shows 30m.
B2 R2 — build job timeout is unchanged at 60m in the same rendered pipeline.
A1 naming or comment style inside the changed hunks.

Verification Scope
Changed files: 3 — .gitlab-ci.yml, ci/templates/test.yml, docs/ci.md
Inspect boundary: those paths, plus call and reference sites reachable from them
Out of boundary: every other path, repo-wide search, dependency audit, full test suite
Proof budget: diff inspection only (no commands; R1/R2 are static configuration)

Verdict evidence must include:
DoD checked: B1 pass, B2 pass, A1 noted
Inspected: {paths read} or diff-plus-call-sites
```

## What this prevents

- `Allowed files` lists 4 paths but the diff touched 3: the fourth is not reviewed.
- `docs/ci.md` is in the diff, so it is in scope; `ci/templates/deploy.yml` is not,
  even though it is the same directory.
- A criterion that cannot be judged inside the boundary comes back as
  `[STUCK] brief defect: B2 needs ci/variables.yml`, not as a wider review.