# 0006: Modular and replayable onboarding

## Decision

Implement onboarding as a versioned, app-only feature with five ordered steps
and a pure state model separate from its SwiftUI presentation. Present it
automatically when the stored acknowledged version is older than the current
version, and expose a Getting Started action on the deck-list toolbar that can
present it again at any time.
The steps explain the existing app/system controls; they do not embed duplicate
import or configuration workflows. Users dismiss the guide to act, then replay
it to check their progress. Config instructions follow ADR 0007's screen layout.

## Why

Import, mapping, deck setup, widget installation, and widget deck selection span
both app-owned and system-owned UI. A one-time hard-coded welcome screen would
be difficult to test and useless after dismissal. A replayable state machine can
be unit tested, previewed from any step, and reused when the workflow changes.

## Alternatives considered

- A static first-launch sheet — rejected because it cannot reflect progress or
  be usefully replayed.
- Force users to finish onboarding — rejected because widget installation is
  optional and partly controlled by iOS.
- Store onboarding state in SwiftData — rejected because it is app preference
  state, not library data.

## Consequences

Completion is advisory and must never block normal app use. Observed app state
adds checkmarks but never moves the user automatically. Dismiss and Finish both
acknowledge at least the current version during automatic presentation without
ever downgrading a newer stored value. Manual replay does not write
acknowledgement state; Restart only returns to step one.
