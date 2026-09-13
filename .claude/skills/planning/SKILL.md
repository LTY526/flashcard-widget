---
name: planning
description: "Turn an idea into a verified spec + ADR file, committed to the repo, then a Ready GitHub issue that points at them. An independent, unbiased sub-agent reviews the actual files and can reject them; the user can overrule a rejection. Never writes production code."
---

# planning

Turns a raw idea into two committed files plus one Ready GitHub issue that only ever *points*
at those files. This skill never touches production code — it only produces (or rejects) a
decision + a spec.

Order is fixed and enforced: **files exist and are committed before the issue is opened.**
`loop` reads the spec from the repo, not from the issue body — a doc that's still uncommitted
isn't real yet.

## Files

- **ADR** — `docs/decisions/<NNNN>-<slug>.md`: the decision and why, alternatives considered,
  consequences. `<NNNN>` = one past the highest existing number in `docs/decisions/` (`0001` if
  none exist).
- **Spec** — `docs/specs/<slug>.md`: goal, acceptance criteria (a checklist, each item concrete
  and testable), scope-out (what this deliberately does not cover).

## Steps

1. **Draft both files** from the user's idea (content below). Write them to disk but do **not**
   commit yet.

2. **Independent verification.** Dispatch a fresh sub-agent (`Agent` tool, no `fork` — it must
   NOT inherit this conversation, that's what makes it unbiased). Hand it the two file *paths*
   and tell it to read them itself, not a paraphrase. Prompt it as an adversarial reviewer:

   > Read `docs/decisions/<file>.md` and `docs/specs/<file>.md`. You did not write these and
   > don't know why they were proposed. Review them only on the merits: does the ADR's
   > reasoning actually hold up? Is the spec unambiguous enough to build blind, and is every
   > acceptance criterion actually checkable? Is anything missing, contradictory, or too risky
   > to greenlight? Reply with a verdict of APPROVE or REJECT and your reasons.

3. **On APPROVE** — commit, then open the issue:
   ```
   git add docs/decisions/<n>.md docs/specs/<slug>.md
   git commit -m "Add ADR <NNNN> and spec for <slug>"
   gh issue create --title "<short specific title>" --label ready --body "<see format below>"
   ```

4. **On REJECT** — show the user the verifier's objections verbatim. Ask directly: fix the files
   and resubmit, or overrule and commit anyway?
   - **Fix** → revise the files, go back to step 2 (re-verify — don't skip it because they
     changed once already).
   - **Overrule** → append a `## Verifier objections (overruled by user)` section to the spec
     file with the objections, then commit and open the issue exactly as in step 3 — never
     silently; the record travels with the file, not just the issue.

5. **Hard order check before `gh issue create`**: run `git status --porcelain docs/decisions
   docs/specs` — it must be **empty** (both files committed). If it isn't, commit first. Never
   open the issue while either file is only on disk uncommitted.

6. **Never build.** If asked to also implement it, decline — hand off to `loop` instead. This
   skill's only output is two committed files and one issue (or a rejection with no issue).

## Issue body format

The issue is a pointer, not a duplicate of the files:

```
## Spec docs touched
- docs/decisions/<NNNN>-<slug>.md
- docs/specs/<slug>.md

## Summary
<one or two sentences — what this is, for the reader who won't open the files>
```

## ADR file format (`docs/decisions/<NNNN>-<slug>.md`)

```
# <NNNN>: <decision title>

## Decision
<what was decided>

## Why
<the reasoning / problem it solves>

## Alternatives considered
- <alternative> — <why not>

## Consequences
<what this commits us to>
```

## Spec file format (`docs/specs/<slug>.md`)

```
# <slug>

## Goal
<why this exists, one or two sentences>

## Acceptance criteria
- [ ] <testable criterion>
- [ ] <testable criterion>

## Scope-out
- <deliberately not covered>
```
