# Troubleshooting

[Documentation index](../README.md)

## Unable to Open Library: groupContainerUnavailable

The installed signature cannot access the configured App Group, or the group is
missing from one target.

1. Check both targets use the same development team.
2. Check both Signing & Capabilities pages enable
   group.com.xyz7172.flashcard-widget.
3. Install directly from Xcode and launch the app once.
4. If only a re-signed/SideStore build fails, its profiles likely do not grant
   the shared group; changing SwiftData code cannot repair that signature.

## Widget selector closes or has no decks

The extension could not query the shared store, no usable deck exists, or its
saved entity is stale. First confirm the app opens normally and has an imported,
mapped deck. Then remove/re-add the widget. If Xcode install works but sideload
does not, investigate App Group signing.

## Widget does not update after Next

Next rebuilds are deliberately debounced for one second. After that, the app
requests a timeline reload, but WidgetKit decides when to redraw. Confirm the
app's current card changes, wait briefly, and test on a real configured widget.
Repeated Next taps should create one rebuild rather than one per tap.

## App shows an old card after returning

Foreground reconciliation should finish before deck content becomes
interactive. If Next jumps to the correct later card but the initial display is
old, inspect the activation gate, exclusive-lock result, fresh context save,
and visible-context refresh.

## Cards progress during sleep hours

Check the deck's stored scheduling timezone and sleep boundaries. An entry that
starts before sleep is extended across the sleeping duration. For example, a
30-minute card beginning at 23:50 with sleep 00:00–08:00 schedules the next card
at 08:20. Test overnight and DST boundaries with an explicit calendar/timezone.

## Paused deck continues changing

Pausing must clear future queue entries and request a widget reload. WidgetKit
may briefly retain an old rendered snapshot, but no valid future entries should
remain. Inspect the paused flag, queue contents, and provider state separately.

## Schedule runs out

The persistent queue holds up to 100 future cards; widget batches hold only five
entries. The app tops up/reconciles on activation. If the app is not opened long
enough to exhaust all 100 entries, the widget has no background writer that can
extend the persistent queue indefinitely.

## Import fails

Use the displayed ApkgImportError category, then check that the package contains
a supported collection, is not corrupt, and uses a supported compression/schema
variant. A failed import should roll back completely; verify no partial deck was
saved before debugging subsequent mapping or schedule behavior.
