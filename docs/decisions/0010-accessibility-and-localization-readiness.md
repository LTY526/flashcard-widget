# 0010: Accessibility and localization readiness

## Decision

Audit every app/widget state for VoiceOver, Dynamic Type, and sufficient
contrast, and move user-facing text into a String Catalog. Treat accessibility
behavior and locale-correct date/time formatting as acceptance requirements for
the current interface, not optional polish.

## Why

Card content is text-heavy, settings use compact controls, and the widget has
strict dimensions. These are precisely the places where large text, screen
readers, contrast, and longer translations reveal hidden assumptions. Doing the
audit after the planned screen restructuring avoids fixing obsolete layouts.

## Alternatives considered

- Audit only the widget — rejected because import, mapping, schedule, and config
  flows must also remain usable.
- Add translations immediately — rejected until strings are catalogued and the
  base-language UI is localization-ready.
- Rely solely on automated checks — rejected because widget/system UI and
  reading order require device verification.

## Consequences

Layouts may need to reflow rather than scale in place. Tests and a manual device
checklist become part of maintaining the accessibility contract. This decision
prepares localization infrastructure but does not select translation languages.
The audit follows the four planned app workflows named in the spec. It covers
the shipping widget without making experimental presentation options or backup
a prerequisite. Imported content stays data rather than becoming catalog keys.

Contrast checks use [WCAG 2.1](https://www.w3.org/TR/WCAG21/), specifically
1.4.3 for text and 1.4.11 for meaningful non-text indicators; this is a UI
acceptance target, not a claim that an automated audit establishes full WCAG
conformance.
