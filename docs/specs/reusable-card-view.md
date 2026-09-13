# reusable-card-view

## Goal

Extract a single reusable SwiftUI view for "how a card is displayed" —
primary text on top, secondary text below it, and an optional tertiary
section for in-app-only extra detail, in a large rectangular card shape —
and adopt it everywhere a card preview currently exists (or is being
added), per
[0002](../decisions/0002-active-card-history-and-display-config.md), so the
in-app preview always matches what the eventual widget will show. This spec
does not create a WidgetKit extension target.

## Acceptance criteria

### Tertiary field role

- [ ] `FieldRole` gains a `tertiary` case alongside the existing `primary`
      and `secondary` cases.
- [ ] `FieldMappingView`'s per-field picker offers "Unused", "Primary",
      "Secondary", and "Tertiary" (previously only the first three).
- [ ] `Note` gains a `tertiaryText: String?` computed property, aggregating
      fields mapped to `.tertiary` the same way `primaryText`/
      `secondaryText` already aggregate their roles.
- [ ] `FieldMappingView`'s live preview reflects tertiary the same way it
      already reflects primary/secondary: driven by the in-progress
      (unsaved) picker selections, updating immediately as the user changes
      the tertiary mapping.
- [ ] An automated test maps a field to `.tertiary` and asserts
      `Note.tertiaryText` returns that field's value, consistent with the
      existing `primaryText`/`secondaryText` test coverage.

### `CardWidgetView`

- [ ] A `CardWidgetView` SwiftUI view exists, taking primary, secondary,
      and tertiary text as three independent, plain `String?` inputs (not a
      `Note` or `Card` directly), so it can later be reused by code that
      doesn't have a live SwiftData object available (e.g. a future
      WidgetKit extension reading from an App Group store).
- [ ] `CardWidgetView` renders primary text prominently in the top portion
      of a large rectangular card shape, secondary text below it, and
      tertiary text (when non-`nil`) below secondary, visually
      de-emphasized relative to secondary. When secondary and/or tertiary
      is `nil`, the view still renders correctly (no empty gap that looks
      broken).
- [ ] When primary text is `nil` (e.g. an unmapped note type), the view
      shows a clear placeholder state rather than blank space, consistent
      with the existing "No field mapped to Primary yet" messaging in
      `FieldMappingView`.
- [ ] `CardWidgetView`'s primary/placeholder/secondary/tertiary
      text-selection logic is implemented as plain, directly testable
      functions (e.g. a small value type or static functions the view calls
      into), not logic buried only inside the view's `body` — this project
      has no snapshot- or view-inspection-testing dependency today, so this
      logic must be verifiable without one.
- [ ] `FieldMappingView`'s existing sample preview is replaced with
      `CardWidgetView`, fed by the same in-progress (unsaved) selection
      state it already tracks (now including tertiary) — the "Try another
      card" behavior and live-updating-as-you-change-the-picker behavior
      are preserved exactly as they work today.
- [ ] Deck Detail's per-deck active-card display (from
      [active-card-deck-management](active-card-deck-management.md), if
      already built, or built/updated as part of this spec if not) renders
      that deck's active card using `CardWidgetView`, fed by that card's
      note's `primaryText`/`secondaryText`/`tertiaryText`.
- [ ] A preview provider (`#Preview`) exists for `CardWidgetView` covering:
      all three fields populated, tertiary `nil`, secondary and tertiary
      both `nil`, and primary `nil`.
- [ ] An automated test (Swift Testing, matching this project's existing
      `flashcard-widget-tests` approach — no new snapshot/view-inspection
      dependency is added) calls the plain functions from the
      text-selection-logic criterion directly and asserts: given primary,
      secondary, and tertiary text, all three are returned/selected as
      expected; given `nil` secondary or `nil` tertiary, that section is
      not selected; given `nil` primary, the placeholder text is selected
      instead of the primary.

## Scope-out

- Any actual WidgetKit extension target, timeline provider, or App Group
  container — separate future spec per
  [0001](../decisions/0001-anki-lockscreen-widget-architecture.md). That
  future spec also decides whether/how a real widget renders `tertiary` (it
  exists specifically because a real Lock Screen widget likely won't have
  room for it, per [0002](../decisions/0002-active-card-history-and-display-config.md)),
  not this one.
- Visual theming/branding beyond a functional, legible layout — no design
  direction exists yet, matching the same scope-out already established in
  [apkg-import](apkg-import.md).
- Rendering media (images/audio) inside the card view — still out of scope
  per [apkg-import](apkg-import.md).
- Any layout other than the single large-rectangular, primary-top/
  secondary/tertiary-bottom shape (e.g. a compact/small variant) — one
  shape is in scope; additional widget-family layouts are future work once
  a real WidgetKit extension exists.
