# APKG import pipeline

[Documentation index](../README.md) | [Data model](data-model.md)

ApkgImporter converts an Anki package into the shared SwiftData graph while
preserving stable identifiers for safe re-import.

~~~text
APKG ZIP -> package loader -> Anki SQLite parser -> parsed values
         -> model upsert -> media copy -> mapping/schedule repair -> save
~~~

## Stages

| Stage | Owner | Purpose |
|---|---|---|
| Archive access | ZipArchiveReader | Reads central directory and extracts members |
| Collection selection | ApkgPackageLoader | Chooses legacy/modern collection and decompresses Zstd when needed |
| Schema detection | CollectionSchemaDetector | Routes supported Anki schema variants |
| Parsing | LegacyCollectionParser / ModernCollectionParser | Produces parser-neutral ParsedCollection values |
| Persistence | ApkgImporter | Upserts note types, fields, notes, cards, and decks |
| Media | MediaImporter | Copies referenced files and records MediaItem rows |
| Mapping | FieldMappingService | Applies safe automatic field-role guesses |
| Scheduling | DeckScheduler | Repairs or seeds usable deck queues |

## Transaction behavior

Import work uses a background ModelContext under the exclusive schedule lock.
The importer delays its final save until the graph is coherent. On failure it
rolls back and exposes an ApkgImportError instead of leaving a half-imported
deck. Widget reload is requested only after success.

## Re-import

Anki IDs match existing objects. Changed values are updated; missing cards are
handled by the import/deletion rules; shared notes and media remain if another
deck still references them. Mapping and current schedule state should be
preserved when still valid rather than blindly reset.

## Native dependencies

SQLiteConnection reads the Anki database only. The bundled Zstandard C source
supports compressed modern collections through ZstdDecompressor. Neither is
used to access the app's own SwiftData store.

Tests use small APKG fixtures for supported versions, corruption, missing
members, removed cards, mapping fallbacks, and atomic failure.
