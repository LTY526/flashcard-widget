# modular-replayable-onboarding

## Goal

Help a new user reach a working widget through independently testable onboarding
that can be dismissed, replayed, and started at any step.

## Integration and step content

Build after `tabbed-deck-detail-and-simplified-config`. The guide is instructional:
it explains existing controls rather than embedding a second importer, mapping
sheet, or configuration form. Users can dismiss it to perform an action and
reopen Getting Started at any time; checkmarks then reflect observed app state.
Next/Back/Restart only navigate the guide. Exact wording and illustration style
are implementation choices; each step must teach the following:

| Step | Required content |
| --- | --- |
| Import deck | Use the root deck-list Import action to select an Anki `.apkg` from Files; wait for completion and follow any mapping prompt. |
| Map fields | Choose the primary field and optional secondary/tertiary/quaternary roles. Reopen Field Mapping from the deck's Config mode; explain that decks sharing a note type share its mapping. |
| Configure schedule | Open the deck's Config mode to review interval, sequential/random order, and optional sleep times. Pause/resume is in Current. |
| Add widget | Use the system Lock Screen editor, add the app's rectangular widget, and save the customized Lock Screen. The app cannot install it for the user. |
| Select deck | While editing the Lock Screen, open that widget's configuration and select its Deck. Each widget has its own selection; quaternary content remains app-only. |

## Acceptance criteria

- [ ] A pure onboarding model defines these stable ordered identifiers exactly:
      `importDeck`, `mapFields`, `configureSchedule`, `addWidget`, `selectDeck`.
      It owns current-step index, Next, Back, Restart, Dismiss, and Finish without
      importing SwiftUI or SwiftData. Back is disabled on the first step; Next
      advances one step and becomes Finish on the fifth.
- [ ] Tests can construct the model at any step and verify exact boundary
      navigation, checkmark predicates, dismissal/finish acknowledgement,
      manual Restart semantics, older/current/newer persisted versions, and a
      currentVersion increase.
- [ ] Persistence contains one integer `acknowledgedOnboardingVersion`, default
      zero. The flow auto-presents iff that value is lower than the code's
      positive `currentVersion`. Automatic-flow Dismiss and Finish store
      `max(existingAcknowledgedVersion, currentVersion)`, so an older app cannot
      downgrade a newer value. Raising currentVersion causes one new automatic
      presentation; values newer than the running code are preserved and do not
      auto-present.
- [ ] A `Getting Started` toolbar action on the root deck list presents step one
      manually at any time. Restart is visible during manual presentation and
      only sets the current step to `importDeck`; it does not change the stored
      acknowledged version or any app/library data. Dismiss closes manual replay
      without changing an already stored acknowledgement.
- [ ] Version persistence belongs to an OnboardingPersistence coordinator, not
      the pure navigation model. The model emits dismiss/finish intents. The
      coordinator performs the max-version write for automatic presentation;
      during manual replay, Dismiss and Finish close the flow without any write,
      preserving the existing acknowledged value exactly.
- [ ] The flow covers APKG import, field mapping, deck schedule configuration,
      adding the rectangular Lock Screen widget, and selecting a deck in the
      widget's system configuration. A per-step presentation test verifies the
      required instructions and destinations in the table above. The guide never
      starts an import, changes mappings/configuration, or changes the schedule.
- [ ] The first three steps show an independent completion checkmark using these
      exact predicates: Import is complete when at least one Deck exists; Mapping
      is complete when at least one deck has `needsFieldMapping == false`;
      Configure is complete when at least one unpaused, mapped deck has a
      non-nil DisplayConfig, matching non-nil active pointer/watermark, and a
      current entry owned by that deck for which `DeckScheduler.isRenderable`
      is true and the note has non-nil primary text. Widget steps never show
      inferred completion.
- [ ] Completion checkmarks are recomputed from injected plain observed-state
      values when the presentation refreshes. They never skip, reorder, dismiss,
      or automatically navigate steps and are not prerequisites for Next/Finish.
- [ ] A user can skip forward, go backward, dismiss, or finish without any step
      blocking ordinary app functionality. Every user dismissal route, including
      a sheet's swipe-to-dismiss gesture, emits Dismiss and follows the same
      automatic/manual persistence rule. Present after successful library
      activation; do not present over a file picker, mapping sheet, or another
      modal. Defer a pending automatic presentation until that modal closes.
- [ ] Every step supports VoiceOver and accessibility Dynamic Type sizes, and
      instructions do not rely on color or imagery alone.
- [ ] Debug previews/test hooks can present any individual step without changing
      production onboarding persistence.

## Scope-out

- Interactive control of the iOS Lock Screen editor.
- Analytics, accounts, cloud-synced onboarding state, or mandatory tutorials.
- Resetting application/library data.
