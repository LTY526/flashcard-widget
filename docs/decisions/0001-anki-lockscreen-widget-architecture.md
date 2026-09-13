# 0001: Architecture for Anki-deck Lock Screen widget app

## Decision

Build the app in phases, starting with a standalone `.apkg` import pipeline, on
these architectural commitments for the whole roadmap:

1. **Parse `.apkg` with an independent, from-scratch parser.** Do not vendor or
   port any code from the Anki desktop/AnkiDroid codebases. Treat `.apkg` as
   "zip containing a SQLite database, possibly zstd-compressed" and write our
   own reader against that container format — see the note on `.anki21b`
   below, which materially affects what "independent parser" has to handle.
2. **No direct integration with AnkiWeb.** The app never talks to AnkiWeb's
   sync servers, official or reverse-engineered.
3. **AnkiConnect is out of scope for v1**, and if ever added, is an optional
   power-user feature, never the primary sync path.
4. **Field-to-role mapping is user/deck-configured, not hardcoded.** Per note
   type, the user (or a heuristic default) maps fields to semantic display
   roles (`primary`, `secondary`, ...) rather than the app assuming fixed
   field names like "Expression"/"Meaning".
5. **Persistence is SwiftData**, shared with the future widget extension via
   an App Group container.
6. **Notes and cards are never hard-deleted by automatic reconciliation,
   only soft-deleted — user-initiated deck removal (decision 8) is the one
   deliberate exception.** When a re-import shows a note or card no longer
   exists upstream, the app flags its row as removed instead of deleting
   it, so any history/progress a future scheduling phase attaches to it
   survives a deck update. This has to cover notes as well as cards: a
   card has no content of its own — its displayable text lives on its
   parent note — so soft-deleting only the card while hard-deleting its
   note would leave a "preserved" card pointing at data that no longer
   exists. The one place this app *does* hard-delete is when the user
   explicitly removes a deck — that's deliberate user intent, not a
   passive side effect of importing an updated file, so there's no future
   history to protect.
7. **Widget refresh is treated as budgeted and coarse-grained**, not a live
   countdown — see rationale below. Any "interval" the user configures is a
   *scheduling* concept (how the app assigns cards to future timeline slots),
   not a guarantee WidgetKit will render at that exact cadence.
8. **Removing a deck is a hard delete.** Tapping "Remove" on a deck
   permanently erases that deck, its cards, and any note (plus its media
   files on disk) that has no *active* card left outside the deck being
   removed. A note with an active card in another deck survives untouched.
   A note whose only other card is itself soft-deleted does not count as
   surviving elsewhere and is erased too — otherwise it would leak forever
   with no path to ever being cleaned up.
9. **Field-role mapping is an always-editable setting, not a one-time
   onboarding step.** The user can reopen the mapping sheet for any deck at
   any time — not just for newly-imported, unmapped note types — and
   change primary/secondary/unused per field. Because mapping is keyed by
   note type (decision 4), not by deck, editing it from one deck's context
   changes how every other deck sharing that note type displays too; there
   is no per-deck override.

This ADR covers the whole roadmap; only the first slice (`.apkg` import → data
model) is scoped into a spec/issue now. Scheduling engine, the WidgetKit
extension, and any future Anki-sync feature each get their own ADR/spec pass
before implementation.

## Why

**Parsing `.apkg` independently is legal; reusing Anki's code is not free.**
Anki (desktop) is licensed AGPLv3. The `.apkg` container itself — a zip
holding a SQLite collection file plus media — is not itself a protected
format; independent readers for it are common (e.g. AnkiDroid, various
Python/Go libraries) and don't trigger AGPL obligations, because copyright
covers the code you copy or derive from, not the shape of a file you
interoperate with. Copying Anki's own parsing code, by contrast, would carry
AGPL's copyleft obligations with it. Writing our own reader keeps us clear
of that — but "our own reader" is a bigger job than it sounds: since Anki
2.1.50 (2021), the default export container is `.anki21b`, where the
collection database is zstd-compressed before being placed in the zip, on
top of a newer relational schema (dedicated `notetypes`/`decks`/`fields`
tables) versus the older schema's JSON blobs in a single `col` row. Most
`.apkg` files a user exports today are `.anki21b`. Apple's `Compression`
framework does not include a zstd algorithm (confirmed against current
WidgetKit-era `Compression` framework docs: it offers LZFSE, LZ4, LZMA,
zlib, Brotli, LZBITMAP, LZMESH, LZRAVEN — no zstd), so decompressing
`.anki21b` requires pulling in a third-party zstd implementation (e.g. a
Swift wrapper over the C `zstd` library). This is a real, scoped dependency
decision, not a detail to discover mid-implementation — the import spec
must say explicitly which container variants (legacy `.anki2`/`.anki21`
JSON-schema, and modern `.anki21b` relational-schema) are in scope.

**AnkiWeb's Terms of Service explicitly forbid third-party client access.**
AnkiWeb's Terms and Conditions (ankiweb.net/account/terms) state: "Because
other clients can cause problems, AnkiWeb does not currently allow access
from browser extensions or other third-party clients. Instead, please use
AnkiConnect, which lets you modify your local connection over a web socket
without any negative impact on AnkiWeb." Note what that sentence is actually
saying: AnkiConnect is offered as a substitute for talking to your *local*
Anki install, not as a sanctioned way to reach AnkiWeb's sync servers — there
is no sanctioned third-party path to AnkiWeb itself. Any "sync automatically
with your Anki account via AnkiWeb" feature would be a ToS violation, not
just a technical risk — so it's excluded outright, not just deprioritized.

**AnkiConnect doesn't fit a mobile-first Lock Screen widget.** AnkiConnect is
a desktop Anki add-on exposing a local HTTP API (default `127.0.0.1:8765`).
It only works while the desktop app is open and, to be reachable from an
iPhone, requires exposing it beyond localhost (binding `0.0.0.0` plus an API
key) on the same LAN as the phone. That's a real constraint for a "check my
Lock Screen while out and about" use case — it only ever works at home with
the desktop app running. It's plausible as an optional sync source later, but
building the whole personalization story around it now would block the app
on a desktop being on and reachable, which defeats the point of a phone
widget. Starting from a self-contained `.apkg` import removes that
dependency; direct Anki sync can be revisited as an added option.

**WidgetKit Lock Screen widgets are not a real-time display surface.**
Apple's own WidgetKit documentation ("Keeping a widget up to date") states
timeline entries should be at least ~5 minutes apart, and that "for a widget
the user frequently views, a daily budget typically includes from 40 to 70
refreshes. This rate roughly translates to widget reloads every 15 to 60
minutes, but it's common for these intervals to vary due to the many factors
involved." That's a direct paraphrase of Apple's stated behavior, not our own
arithmetic on the 40-70 figure — the docs themselves note reloads aren't
spread evenly across the day, so a wider effective-cadence range than naive
even-spacing math would suggest is expected and system-tuned per user, not a
contradiction. Either way, a config value like `"interval": 30` (seconds) is
not something WidgetKit can honor. However, **interactive App Intents
(buttons) inside a widget do not count against the reload budget** — so a
"flip card" / "show answer" button on the widget can feel responsive even
though the system's own timeline refresh is coarse. This shapes the whole
scheduling design: "interval" configures how far apart *scheduled* cards are
placed in the timeline (with a sensible floor — see Consequences), not a
literal on-screen countdown; within a single scheduled card, a flip button
gives the interactive feel the user actually wants.

**Notes and cards must survive being removed from an updated deck.** Anki
decks change over time — the user edits a deck and re-exports, and some
notes/cards disappear from the new `.apkg` (typos fixed by splitting a note,
cards deleted, decks reorganized). If a re-import hard-deletes whatever's no
longer present, any per-card state a later phase builds — review history,
"cards already seen today," schedule position — is destroyed right along
with it, silently, on every deck update. Since this app's whole point is to
track per-card display/scheduling state over time, that state has to
outlive the source deck's edits. Soft-deleting (flag as removed, keep the
row) costs one boolean/timestamp column per row and means later phases
don't have to special-case "the history for a card whose note no longer
technically exists" — which is why the note itself has to be soft-deleted
too, not just the card that points at it.

**Field mapping must be user-driven because note types vary.** The user's
primary use case is Japanese vocabulary decks, but "Japanese vocab note type"
isn't one fixed schema across the Anki ecosystem — popular templates differ
(e.g. Expression/Reading/Meaning vs. Front/Back vs. Kanji/Kana/English), and
any deck the user or a shared-deck author created may add extra fields
(sentence examples, mnemonics, audio references). Hardcoding field names
would break on the first deck that doesn't match. Letting the user map
fields to roles once per note type keeps the app generic while still solving
the Japanese use case well, since a `primary`/`secondary` role pair maps
naturally onto "front, then reveal reading + meaning."

**Deck removal needs to actually free the user's storage and let them start
over.** A soft-delete-forever policy would mean every experimental import a
user tries — a shared deck they end up not liking, a mis-imported file —
permanently occupies storage and clutters internal state, with no way to
truly undo it short of manually editing the database. Removal is an
explicit, deliberate user action, not a side effect of an automatic
re-import, so there's no future scheduling history to protect: there's
nothing worth preserving for a deck the user affirmatively said they don't
want anymore. The one real nuance is shared notes — a note's cards can in
principle span more than one deck — so removing deck A must check whether a
note has an *active* card in deck B before erasing it, not merely whether
some card of the note happens to sit in deck B: a note whose only other
card was already soft-deleted (say, by an earlier re-import) has nothing
active anywhere anymore, and treating it as "still shared" would leak that
note and its media permanently, with no re-import or future removal ever
able to reach it again. Removal must also delete the note's copied media
files from disk, not just its SwiftData rows, since the user asked for
full removal, not just hiding.

**Mapping needed to be revisitable, not one-shot.** Requiring the user to
get a note type's field roles exactly right during the first-ever import
prompt is an unreasonable bar — you often can't judge which field should be
"primary" until you've seen a few real cards, and preferences change.
Making mapping an always-available action (a swipe action next to Remove,
and tapping the existing "needs mapping" badge) removes that one-shot
pressure. The cost is that mapping remains a single setting shared across
every deck using that note type (decision 4 already established this
sharing); this ADR is not resolving whether mapping should become per-deck
instead of purely per-note-type — that's flagged as an open question for a
future pass, now that editing is a casual, frequent action rather than a
rare onboarding step, not a decision made here.

**UI mockups are deliberately not part of this ADR/spec.** The user has no
design direction yet; this skill produces a decision + spec, not visuals.
Visual design should be its own pass (e.g. a follow-up planning cycle or
direct design exploration) once the data/import layer exists to build
against, rather than guessing at a UI now.

## Alternatives considered

- **Vendor/port Anki's own `.apkg` reading code** — rejected: pulls in AGPL
  obligations and Rust/Python code not easily portable to Swift anyway.
- **Sync via AnkiWeb directly** — rejected outright: explicitly disallowed by
  AnkiWeb's Terms of Service.
- **Make AnkiConnect the primary sync mechanism** — rejected for v1: requires
  desktop Anki open and network-reachable from the phone, which doesn't hold
  for a Lock Screen widget meant to be useful away from the desktop. Left as
  a possible optional feature later.
- **Hardcode field roles for a "standard" Japanese note type** — rejected:
  Japanese-vocab note types aren't standardized enough across shared decks;
  a user-configured mapping generalizes without much added complexity.
- **Treat widget "interval" as a literal refresh countdown** — rejected: not
  achievable under WidgetKit's documented reload budget; would ship a config
  option that silently doesn't work as labeled.
- **Core Data instead of SwiftData** — rejected: project already uses
  SwiftData (see `flashcard_widgetApp.swift`); no reason identified to
  introduce a second persistence stack.
- **Hard-delete notes/cards removed from a re-imported deck** — rejected:
  destroys any per-card history/scheduling state a later phase attaches,
  silently, on every routine deck update; soft-deleting only cards while
  hard-deleting their notes would still orphan a "preserved" card's content.
- **Soft-delete decks the same way notes/cards are soft-deleted on
  re-import** — rejected: gives the user no way to actually free storage or
  fully undo an import they regret; removal is deliberate user intent,
  unlike passive re-import reconciliation.
- **Add a per-deck field-mapping override instead of keeping mapping purely
  per-note-type** — deferred, not rejected: real added complexity (a
  mapping table keyed by (deck, note type) instead of just note type) with
  no concrete use case yet; revisit if a real deck surfaces a genuine need
  for divergent mappings of the same note type.

## Consequences

- We own and maintain a `.apkg`/SQLite parser ourselves — more upfront work
  than wrapping an existing library, but no licensing entanglement.
- We take on a third-party zstd decompression dependency (Apple's
  `Compression` framework doesn't cover it) to support `.anki21b`, the
  container format most real-world `.apkg` exports use today.
- No "just works" background sync with a user's live Anki reviews in v1;
  personalization comes from periodically re-importing an updated `.apkg`
  export until/unless an AnkiConnect-based option is added later.
- The scheduling config's `interval` field needs a floor (recommend 15
  minutes minimum, default higher) and documentation that it's advisory, not
  exact — this must be surfaced in the config UI copy so users aren't
  surprised the widget doesn't flip every 30 seconds.
- Every new Anki note type layout needs a one-time field-mapping step from
  the user before its deck displays meaningfully; this is a real interaction
  cost we're accepting in exchange for not hardcoding formats.
- The widget extension (future phase) will need an App Group container set
  up between the main app and the extension target to share the SwiftData
  store — not yet configured in the Xcode project.
- Deck removal must check *active* card membership, not raw card
  membership, when deciding whether a note "survives elsewhere" — get this
  wrong in one direction and a shared note gets deleted out from under a
  deck still actively using it; get it wrong in the other (checking any
  card, active or soft-deleted) and a note orphaned by an earlier
  re-import leaks permanently once its last active reference is removed,
  since nothing else in the app ever revisits an already-removed deck.
- Field mapping edits are global and immediate: there's no confirmation
  step beyond the mapping sheet itself, and no per-deck isolation. A future
  phase needing per-deck display divergence would require a real
  data-model change (mapping keyed by (deck, note type), not just note
  type).
- Both import and deck removal run against a background `ModelContext` on
  the same `ModelContainer`, resolved back into the main context by
  `PersistentIdentifier`, so the UI stays responsive during either
  operation. Any future phase that also mutates this store (e.g. a
  scheduling engine writing review state) should follow the same pattern
  rather than blocking the main actor.
- `.apkg` must be declared as an imported `UTType` in the app's Info.plist
  (conforming to `public.zip-archive`), not just constructed at runtime via
  `UTType(filenameExtension:conformingTo:)` — the latter is invisible to
  the out-of-process file picker and causes matching files to appear
  greyed out and unselectable.
