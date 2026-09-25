# 0005: Paginated and detailed schedule history

## Decision

Keep complete reached-card history, but stop materializing the entire history to
display one page. Past rows use keyset pagination on the per-deck unique,
immutable sequence: the screen captures its reconciled watermark as an upper
bound, then fetches newest-first 20-row pages below the last returned sequence.
Upcoming captures the current entry plus the persisted future queue, then shows
20 rows at a time from that bounded session value. The Schedule UI shows the
queue horizon even before the final row is visible and lets a past row expand to
display all four mapped text roles as they exist when that page is fetched.

## Why

UI-only pagination currently builds and sorts every history row before taking a
small prefix. That becomes slower as a deck accumulates years of progress.
Users also need to inspect an old card without making every collapsed row tall.

## Alternatives considered

- Delete old history — rejected because the user prefers a complete record.
- Continue loading everything and paginate only the visible list — rejected
  because it does not reduce database or memory work.
- Show every field in every row — rejected because it makes scanning difficult.

## Consequences

Schedule reads need value projections and database-backed paging independent of
the live Deck relationship. A screen session is a snapshot boundary: progress
that advances afterward appears after refresh/re-entry, not midway through old
pages. History stores card references rather than immutable text snapshots, so
re-imported/mapped text is intentionally reflected by later page fetches.
Successful foreground activation also begins a new session. Session resets
replace paging and expansion state together while preserving Upcoming/Past
selection; switching those subsections alone does not refresh. The performance
contract covers complete scheduling transactions as well as their selectors.
Upcoming Load More reveals more of the already captured queue without a database
fetch or a new session.
