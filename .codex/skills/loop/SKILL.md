---
name: loop
description: "Execute the next Ready GitHub issue — build via an Engineer sub-agent, verify via an independent QA sub-agent that never trusts the Engineer's self-report, then PR/merge. Never designs — an ambiguous issue gets blocked back to planning, not guessed at."
---

# loop

Execution only. Never makes a design decision — if an issue is ambiguous, block it and move on;
that gap gets fixed by the `planning` skill, not by improvising here.

## Steps

1. **Find work**: `gh issue list --label ready --state open --json number,title,body,labels`.
   Skip anything already labeled `in-progress` or `blocked`. Pick the lowest issue number.
   No ready issue → report idle and stop (don't spin).

2. **Pick it**:
   ```
   git fetch origin main
   git checkout -b task/<n>-<slug> origin/main
   gh issue edit <n> --add-label in-progress --remove-label ready
   ```
   Read the `## Spec docs touched` paths out of the issue body, then **open those files** —
   the spec file's acceptance criteria are the real contract, the issue body is just a pointer
   to them. No `Spec docs touched` section, or a path that doesn't exist → this issue skipped
   `planning`; block it (step 5's commands) instead of guessing the acceptance criteria.

3. **Build** — dispatch a fresh Engineer sub-agent (`Agent` tool) with the spec file's contents
   (not this conversation, not a paraphrase). Instruct it: implement this, test-first — write
   the acceptance test(s) first, confirm they fail, then implement until they pass. Report back
   what changed and quote the red-then-green transition.

4. **Verify independently** — dispatch a second fresh sub-agent as QA, given the spec file's
   contents plus the diff (`git diff origin/main`). It must NOT be told the Engineer's
   self-report as fact — it re-derives everything itself:
   - Re-run the test suite itself; don't take "tests pass" on faith.
   - Walk every acceptance-criteria checkbox in the spec file against the actual diff, one by
     one.
   - Verdict: PASS, or FAIL with specific unmet criteria / broken tests.

5. **On FAIL** — re-dispatch a fresh Engineer with the QA feedback attached. Max 2 retries (3
   build attempts total). Still failing:
   ```
   gh issue comment <n> --body "<why it's stuck — QA's last verdict>"
   gh issue edit <n> --add-label blocked --remove-label in-progress
   ```
   Move on to the next Ready issue.

6. **On PASS**:
   ```
   gh pr create --title "<title> (#<n>)" --body "Closes #<n>

   <one short summary of what changed and how it was verified>"
   ```
   Merge it (`gh pr merge --squash`) if the user said this session runs unattended; otherwise
   leave it open for the user to merge — ask once at session start which applies, don't ask
   per-issue.

7. **Repeat** from step 1 for the next Ready issue until none remain or the user stops the
   session.
