# v3.53 Scraper review

Fixes:
- Checkpoint resume is now tied to the run (channel + filter text + format). Before, a
  stopped scrape of channel A was silently merged into the next scrape of channel B when
  the file name and order were the same (the default "youtube_data" made this common).
  Old untagged checkpoints are no longer picked up.
- Exports never overwrite an earlier file: if `<name>_<order>.<ext>` exists, a
  `_YYYYMMDD-HHMMSS` stamp is added.
- Amount can no longer be 0 (slider/field minimum 1, Start stays disabled, VM guard).
- The "100 units / 50 results" cost chip now also shows for Most Popular / Most Relevant
  (both use search.list), not only when filter text is typed.
- Log warns when a search-backed run asks for more than ~500 videos (search.list cap).
- XLSX: cells capped at Excel's 32,767-char limit (long transcripts made Excel repair the
  file), and text starting with "=" is stored as text, never as a live formula.

Defaults:
- Worker Threads default 1 -> 3 for NEW installs only (existing configs untouched).
