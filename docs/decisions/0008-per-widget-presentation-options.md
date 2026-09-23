# 0008: Per-widget presentation options

## Decision

Add presentation-only parameters to each widget configuration: one, two, or
three displayed roles; compact, standard, or large text; and hide-versus-dash
behavior for empty optional rows. Keep one rectangular widget family and do not
add privacy/reveal behavior. Every selected role remains one tail-truncated line.
Typography mappings are fixed in the specification, and Hide removes an empty
selected role without substituting a later unselected role.

## Why

Field length and desired information density differ by deck and by Lock Screen.
Widget intent parameters allow two widget instances using the same deck to render
differently without changing the deck, mappings, schedule, or app presentation.

## Alternatives considered

- Store preferences on Deck — rejected because every widget for that deck would
  be forced to share one presentation.
- Automatically infer row count/font size — rejected because unpredictable
  changes make configuration hard to understand.
- Add privacy mode or more families now — rejected by current product scope.

## Consequences

The widget intent gains stable option enums and explicit rendering defaults.
Timeline entries need enough plain content to apply configuration without
touching persistence. Large text intentionally trades character capacity for
legibility rather than adding lines or hiding roles automatically.
