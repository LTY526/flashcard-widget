# accessibility-and-localization-readiness

## Goal

Make all current app and widget workflows usable with accessibility settings and
ready for translation without clipping or locale assumptions.

## Dependencies and evidence

Build after `tabbed-deck-detail-and-simplified-config`,
`scalable-detailed-schedule-history`, `modular-replayable-onboarding`, and
`apkg-import-feedback-and-metadata`, so the audit covers their delivered UI.
Per-widget presentation options and backup/recovery remain separate exploration
work; this issue does not introduce either feature or wait for them. Audit the
widget configurations actually shipped at implementation time. Later features
must extend the resulting accessibility tests and checklist.

`CardWidgetView.swift` currently limits in-app primary/secondary text to two
lines; `FlashcardWidget/FlashcardWidget.swift` owns the actual widget rendering.
Audit both surfaces rather than treating the in-app preview as widget evidence.
Use Apple's [accessibility audit guidance](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
and [String Catalog guidance](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog).

## Acceptance criteria

- [ ] Audit the deck list, onboarding, importer states/results, Field Mapping,
      all three Deck Detail modes, expandable history, store-opening errors, and
      every widget state for VoiceOver, Dynamic Type, and sufficient contrast.
- [ ] Every interactive control has a human-readable accessibility label, value
      where stateful, appropriate trait, and a hint only when its result is not
      clear from the label.
- [ ] VoiceOver traversal follows visual/task order. Card content is exposed as
      primary, secondary, tertiary, then quaternary; empty roles and decorative
      placeholders are not announced.
- [ ] App screens remain operable at all accessibility Dynamic Type sizes.
      Essential app text is multiline/untruncated; controls may reflow or stack
      rather than overlap or become unreachable.
- [ ] The rectangular widget remains legible within fixed bounds at supported
      content sizes and uses documented line limits/scaling. Long content never
      overlaps another row.
- [ ] Text and meaningful graphical controls meet WCAG 2.1 AA contrast in light,
      dark, increased-contrast, and widget rendering modes where the app controls
      foreground/background color. Record measured ratios: at least 4.5:1 for
      normal text, 3:1 for large text (18 pt regular or 14 pt bold and above),
      and 3:1 against adjacent colors for meaningful non-text control indicators,
      applying the exceptions in WCAG 2.1 criteria 1.4.3 and 1.4.11. Record
      system-controlled colors separately rather than claiming they were fixed.
- [ ] All user-facing app, widget, App Intent, error, accessibility, and preview
      strings are represented by localization-aware APIs and a String Catalog;
      no user-visible string is assembled in a way translators cannot reorder.
      This means app-authored UI strings; imported card text, user/deck names,
      filenames, and underlying diagnostic details remain data, interpolated
      into localized messages where applicable. Both app and extension targets
      have access to the catalog entries they use.
- [ ] Dates, times, counts, and sleep ranges use locale-aware FormatStyle APIs.
      Tests cover at least one 12-hour and one 24-hour locale plus longer
      pseudo-localized text.
- [ ] Focused automated tests and a manual device checklist document VoiceOver
      reading order, accessibility text sizes, contrast variants, widget
      configuration, and deep-link navigation. Exercise English plus expanded
      and right-to-left pseudolocalization, and date/time/count examples with
      en_US and en_GB. Record device/OS, tested settings, results, and any
      system-owned limitations in the checklist; unchecked manual items remain
      explicitly unverified.

## Scope-out

- Shipping translations for named languages.
- New visual themes, widget families, or product functionality.
- Accessibility changes to system-owned Lock Screen editing UI.
