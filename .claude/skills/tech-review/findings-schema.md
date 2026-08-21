# Findings schema

The contract every reviewer sub-agent writes and the orchestrator reads. Include this
file's contents in each sub-agent's prompt.

## Where findings go

Write one JSON object to:

```
<scratchpad>/tech-review-<BRANCH>/<source>.json
```

Return only a one-line count to the orchestrator. Do not return the findings themselves.

Two reasons. Findings on disk survive context compaction, so a long review does not lose
its own results. And the orchestrator never ingests a full raw report — one tool's
verbose output does not crowd out another's.

## Shape

```json
{
  "source": "coderabbit",
  "status": "ok",
  "reason": "",
  "findings": [
    {
      "file": "buildconfig/converter.go",
      "line": 412,
      "severity": "blocker",
      "scope": "in-diff",
      "title": "Strategy parameter emitted but never defined",
      "detail": "convertBuildArgs emits \"runtime-stage-from\", which the buildah ClusterBuildStrategy does not define. The BuildRun fails at admission with UndefinedParameter.",
      "confidence": 9
    }
  ]
}
```

## Fields

| Field | Values | Meaning |
|---|---|---|
| `source` | your reviewer's name | Named in the report so a finding can be traced |
| `status` | `ok`, `failed`, `unavailable`, `skipped` | See below |
| `reason` | free text | Required unless `status` is `ok` |
| `findings` | array | Empty when status is not `ok` |

### status

This field is the point of the schema. The old skill logged a warning and continued when
a tool was missing, so a run with one reviewer and a run with four produced identical
output. Say what happened.

- `ok` — the reviewer ran to completion. An empty `findings` array means it genuinely
  found nothing.
- `unavailable` — the tool or skill is not installed or not enabled. Put the name in
  `reason`.
- `failed` — it ran and errored, timed out, or produced output you could not parse.
- `skipped` — a deliberate skip, such as an escalation threshold not being met.

**Never report `ok` with an empty array when you actually mean `failed` or
`unavailable`.** A silent absence reads as a clean result and that is the failure this
schema exists to prevent.

### severity

| Value | Use when |
|---|---|
| `blocker` | Correctness, security, or data loss. Would break a build or ship wrong behaviour. Blockers gate the verdict and are adversarially verified. |
| `warning` | Should be fixed but does not break anything: missing tests, drift, duplication. |
| `info` | Style, reuse, documentation. Never auto-fixed. |

Be conservative with `blocker`. Every one is challenged, and a false blocker stops a good
branch.

### scope

- `in-diff` — the problem is in code this branch changed.
- `pre-existing` — the problem is real but predates the branch.

Pre-existing findings never block the verdict. They are reported separately. Judge by
whether the line appears in the branch diff, not by whether the file does.

### confidence

1-10. Use 9-10 only when you read the code and can cite it. Use 5 or below for a pattern
match you did not verify. The challenger weighs this.

## Rules for every reviewer

- One finding per problem. Do not split one bug across several entries.
- `file` is repo-relative. Never an absolute path.
- `line` is the line in the branch, not in the base.
- `detail` says what is wrong **and** what happens as a result. "Missing nil check" is
  not a finding; "returns nil when spec.source is unset, and the caller dereferences it
  two lines later" is.
- Do not report findings about the local workspace. CI builds this module standalone;
  `GOWORK=off go test ./... -count=1` is authoritative. A problem that only reproduces
  under the workspace is local noise.
- Do not report the absence of a `replace` directive for crane-lib. There is none by
  design; the dependency is pinned to a published pseudo-version. `AGENTS.md` is stale
  on this point and `go.mod` is authoritative.
- Do not write to any file except your own findings JSON.
