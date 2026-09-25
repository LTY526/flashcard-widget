#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

# Only the two SwiftData relationship declarations may name historyEntries in
# production Swift. This catches direct, optional, bare, key-path, and
# subscripted reads without relying on how a caller spells the deck variable.
violations=$(find flashcard-widget FlashcardWidget -type f -name '*.swift' -exec awk '
    /(^|[^[:alnum:]_])historyEntries([^[:alnum:]_]|$)/ {
        if ((FILENAME == "flashcard-widget/Models/Card.swift" ||
             FILENAME == "flashcard-widget/Models/Deck.swift") &&
            $0 ~ /^[[:space:]]*var historyEntries:/) next
        if (index(FILENAME, "flashcard-widget/Models/") == 1 &&
            $0 ~ /^[[:space:]]*\/\//) next
        print FILENAME ":" FNR ":" $0
    }
' {} +)
if [ -n "$violations" ]; then
    printf '%s\n' "$violations"
    echo 'Production code must query HistoryEntry by sequence instead of reading historyEntries.' >&2
    exit 1
fi
