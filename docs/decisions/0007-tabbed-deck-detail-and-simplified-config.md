# 0007: Tabbed Deck Detail and simplified configuration

## Decision

Make Deck Detail a three-mode screen: Current, Schedule, and Config. Remove the
unused new-cards-per-day and previous-day-review options from the UI and
DisplayConfig model. Preserve only settings that currently affect scheduling.

## Why

The existing detail page mixes the primary study action with navigation and
configuration. Three explicit modes make the common Current experience clearer
and keep Schedule and Config close without additional navigation depth. Unused
controls imply behavior the scheduler does not implement.

## Alternatives considered

- Keep the existing page and add more navigation rows — rejected because it
  continues mixing unrelated responsibilities.
- Hide but retain unused model fields — rejected because dead configuration
  remains misleading to maintainers and backup formats.
- Make each mode a separate pushed screen — rejected because rapid comparison
  and configuration would require repeated back navigation.

## Consequences

Deep links target Current. Switching modes must coordinate pending debounced
Next work. Removing SwiftData properties requires verification that existing
installed stores migrate and retain all still-supported configuration.
A root-owned pending-work coordinator makes flush failure visible and retryable
even after Detail disappears; dependent schedule edits wait for successful save.
Migration fixtures retain the old schema as test evidence, while production
models and current usage documentation remove the obsolete settings.
