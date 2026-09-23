---
name: explore
description: "Prototype a feature on an isolated branch and refine it with the user before planning. Use when trying a partial implementation will clarify behavior, UX, or feasibility."
---

# explore

Use this skill when the user wants to see and adjust a feature before its final design is
known. The user's detailed idea is enough to start a small experiment; a complete spec and
Ready issue are not prerequisites. This is an interactive workflow, driven by the user's
reaction to working behavior.

## Workflow

1. **Choose the first question to answer.** Read the user's goal, relevant code, and any
   existing project guidance. Identify the uncertain behavior, experience, or technical
   premise that a runnable slice could clarify. Ask only about a choice needed before that
   slice can be built. Use the background the user already gave or the personal
   developer context profile, if present: in Codex, `$CODEX_HOME/developer-context.md`
   (default `~/.codex/developer-context.md`); in Claude Code, `~/.claude/developer-context.md`.
   If useful context is missing, ask once about familiarity and preferred framework
   analogies. Save those facts in the profile only if the user wants. Explain unfamiliar
   platform concepts without making the user repeat their background.

2. **Isolate the experiment.** Inspect Git status and the intended base. Resume a test
   branch named by the user, or create an explore/<slug> branch (following the repository's
   naming convention) in an isolated worktree when possible. Preserve existing uncommitted changes; do not reset or overwrite them.
   Keep the branch separate from production work.

3. **Build something the user can judge.** Implement the smallest runnable slice that answers
   the first question, often the riskiest interaction or platform behavior. Reuse the
   project's patterns where they fit. Run focused builds, tests, or manual checks that are
   available, commit coherent progress, and state what could not be checked. A prototype may
   be incomplete, but describe its limitations precisely.

4. **Adjust with the user.** Show the actual result through a runnable path, screenshot, or
   clear steps for trying it. Ask for feedback on the concrete behavior and apply the requested
   changes on the same branch. Repeat while the user is shaping the feature; do not impose a
   planning review or a fixed number of rounds. When a technical constraint changes the
   options, point to the relevant code or authoritative platform source, explain the effect
   in ordinary language, and recommend a path. Keep user decisions distinct from agent
   suggestions.

5. **Leave a usable handoff.** When the direction is settled or the user pauses, write
   docs/explorations/<slug>.md on the exploration branch. Record:
   - Goal and the behavior the user confirmed, including feedback that changed the design.
   - Approaches tried and what was learned from each.
   - Open product questions and technical risks, with evidence.
   - Branch and prototype commit(s), checks run, and how to try it.
   - Which code is worth carrying forward, which needs rework, and which was only an experiment.

   Commit the handoff and push the branch when an origin is available so a later planning
   session can inspect it. Give the user the branch/ref and a short summary. Planning turns
   the confirmed decisions into an ADR and testable spec. Prototype code is evidence and
   candidate implementation, not an approved spec or a claim that production work is done.

Do not create a Ready issue or merge the experiment by default. Open a draft PR if the
user wants one for review. The user can also stop after exploration without entering
planning.
