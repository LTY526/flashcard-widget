# Pre-change SwiftData store

`PreChange7f7df1d.store` was generated on an iOS 27 simulator by compiling
`GeneratePreChange7f7df1d.swift.txt` as a Swift Testing file against Git
commit `7f7df1d` and its complete `SharedModelContainer.schema`. The generator
created a file-backed store through `SharedModelContainer.make(at:)`, populated
the deck, config, note type, fields, note, card, current and future history
rows, then saved. The WAL was checkpointed with `sqlite3` before copying this
store. The fixture intentionally retains the removed config columns as
migration evidence.

`PreChangeStoreMigrationTests` copies the fixture to a writable location,
opens that copy with the current production container factory, saves it, then
reopens and compares the retained values and relationships.
