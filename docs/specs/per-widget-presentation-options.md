# per-widget-presentation-options

## Goal

Let each rectangular Lock Screen widget choose its information density without
changing deck data or scheduling.

## Acceptance criteria

- [ ] ConfigurationAppIntent offers Displayed Fields (1, 2, or 3), Text Size
      (Compact, Standard, or Large), and Empty Rows (Hide or Show Dash).
- [ ] Existing/new widget configurations default to three fields, Standard text,
      and Show Dash. The deterministic default is: a leading-aligned VStack with
      spacing 2; primary `.body`, secondary/tertiary `.caption`; one line each;
      tail truncation; primary minimumScaleFactor 0.75; optional rows do not
      scale; and an em dash occupies a nil optional row.
- [ ] Field count selects the mapped roles in order: one shows primary; two show
      primary/secondary; three show primary/secondary/tertiary. Quaternary is
      never shown in the widget.
- [ ] Field count first selects a fixed prefix of roles, then Empty Rows is
      applied. Hide removes nil/empty selected optional roles and reflows the
      remaining selected roles; it never backfills with a later role. Example:
      two fields with empty secondary shows only primary, not tertiary. Show Dash
      retains each selected optional row as an em dash. Primary still uses the
      unavailable/broken-schedule state rather than a dash.
- [ ] Typography is exact: Compact uses `.caption` for primary and `.caption2`
      for optional rows; Standard uses `.body` and `.caption`; Large uses
      `.headline` and `.subheadline`. All selected rows remain one line with tail
      truncation. Only primary has minimumScaleFactor 0.75. Layout never drops a
      non-empty selected row, adds a second line, or changes size automatically.
- [ ] The VStack is vertically centered when all selected rows fit and clipped
      to accessoryRectangular bounds as a final safety measure. Snapshot tests at
      representative rectangular sizes assert every selected row has a
      non-overlapping frame contained in bounds; primary has layout priority 1
      and optional rows priority 0.
- [ ] Options are stored per widget instance. Two widgets selecting the same
      deck can render differently and receive the same scheduled cards.
- [ ] VoiceOver reads only actual non-empty displayed role values, in role order,
      and never announces placeholder dashes.
- [ ] Changing any presentation option causes WidgetKit to request/render an
      updated snapshot but does not save SwiftData, rebuild a queue, advance a
      card, or alter another widget instance.
- [ ] Widget previews and deterministic snapshot/layout tests cover every
      field-count value, each exact typography mapping, both empty-row behaviors,
      intermediate missing roles, long strings, and missing optional roles.

## Scope-out

- Privacy/reveal mode, interactive controls, quaternary widget content, images,
  audio, or additional widget families.
- Per-deck presentation settings or changes to Field Mapping.
