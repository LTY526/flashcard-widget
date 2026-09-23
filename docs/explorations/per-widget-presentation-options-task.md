# Explore per-widget presentation options

Status: prepared for an exploration; no prototype or user feedback is recorded yet.
Branch: `codex/explore-widget-presentation-options`.
Base: `origin/main` at `faa7927` (the five reviewed plans).

## Goal and confirmed scope

Let each rectangular Lock Screen widget choose how many mapped roles to show,
text size, and whether empty optional rows disappear or show a dash. Different
instances selecting the same deck must be able to look different while reading
the same schedule. The widget shows at most primary, secondary, and tertiary;
quaternary remains in the app. Do not add privacy mode or another widget family.

The copied [ADR](../decisions/0008-per-widget-presentation-options.md) and
[spec](../specs/per-widget-presentation-options.md) are **provisional drafts**.
Their exact font mapping, defaults, and layout guarantees are hypotheses for
the experiment, not approved implementation requirements.

## First question to answer

Does the proposed one/two/three-row layout actually fit and remain legible in
the accessory rectangular Lock Screen widget at the proposed Compact, Standard,
and Large text sizes, including accessibility text sizes and long field values?
The app's `CardWidgetView` is only an in-app preview; the real widget rendering
is in `FlashcardWidget/FlashcardWidget.swift`.

## First runnable slice

Add provisional parameters to `ConfigurationAppIntent` for field count, size,
and empty-row behavior, then render those options in the real widget with
preview/demo values. Keep this work isolated on the branch. Try all three row
counts with long text, an empty secondary role, and two widget instances using
one deck but different options. Capture actual Lock Screen or simulator
screenshots at representative device and accessibility sizes. Check VoiceOver
order and that changing presentation does not mutate schedule data or advance a
card. Run the focused widget build/tests available in the repo.

## Feedback and handoff

Show the user the concrete variants and ask which are readable and useful. If
rows overlap, clip, or become illegible, adjust the options on this branch with
the user instead of treating the draft typography table as fixed. Record the
confirmed choices, checks, limitations, reusable prototype commits, and open
questions in `docs/explorations/per-widget-presentation-options.md` when the
direction settles. Push the branch; planning can then revise the draft ADR/spec
and create a Ready issue. Exploration itself creates no Ready issue.
