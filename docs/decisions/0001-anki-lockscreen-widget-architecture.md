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
6. **Notes and cards are never hard-deleted, only soft-deleted.** When a
   re-import shows a note or card no longer exists upstream, the app flags
   its row as removed instead of deleting it, so any history/progress a
   future scheduling phase attaches to it survives a deck update. This has
   to cover notes as well as cards: a card has no content of its own — its
   displayable text lives on its parent note — so soft-deleting only the
   card while hard-deleting its note would leave a "preserved" card
   pointing at data that no longer exists.
7. **Widget refresh is treated as budgeted and coarse-grained**, not a live
   countdown — see rationale below. Any "interval" the user configures is a
   *scheduling* concept (how the app assigns cards to future timeline slots),
   not a guarantee WidgetKit will render at that exact cadence.

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
