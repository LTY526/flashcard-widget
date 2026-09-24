#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
command -v rg >/dev/null 2>&1 || {
    echo 'ripgrep is required to check Schedule history access.' >&2
    exit 1
}

# Only the two SwiftData relationship declarations may name historyEntries in
# production Swift. This catches direct, optional, bare, key-path, and
# subscripted reads without relying on how a caller spells the deck variable.
if rg -n '\bhistoryEntries\b' flashcard-widget FlashcardWidget --glob '*.swift' \
    | rg -v '^flashcard-widget/Models/(Card|Deck)\.swift:[0-9]+:[[:space:]]*var historyEntries:' \
    | rg -v '^flashcard-widget/Models/[^:]+\.swift:[0-9]+:[[:space:]]*//'; then
    echo 'Production code must query HistoryEntry by sequence instead of reading historyEntries.' >&2
    exit 1
fi
