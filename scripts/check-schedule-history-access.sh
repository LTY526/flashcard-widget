#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

# A direct inverse-relationship read in app or widget code would fault the
# complete deck history. Model declarations are excluded because they define
# the relationship rather than read it.
if rg -n '\.historyEntries\b' flashcard-widget FlashcardWidget \
    --glob '*.swift' --glob '!**/Models/**'; then
    echo 'Schedule paths must query HistoryEntry by sequence instead of reading deck.historyEntries.' >&2
    exit 1
fi
