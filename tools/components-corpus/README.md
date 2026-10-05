# Components corpus

What the components inventory (`HatchCore/ComponentInventory.swift`) is tuned and measured on: 62 open-source macOS
apps from different authors, categories and minimum macOS versions, and 14 Apple sample projects (the native look),
listed in `MANIFEST.tsv`. Nothing in the corpus is built or run; the inventory only reads Swift text.

- `fetch.sh <folder>` clones or downloads the corpus (about 2.3 GB).
- `bench.sh <folder> [heldout|tuned] [-v]` rescans the apps and scores the places against two samples of controls a
  reader judged by opening the source: `gold-tuned.json` (221 controls, the rules were tuned on these) and
  `gold-heldout.json` (172 controls, drawn in proportion to how common each place is, never tuned on). `-v` lists the misses with
  the reader's note.

Change a place rule only when it does not lower the held-out score. Results on 2026-10-05: tuned 73%, held-out 68%
(places read from structure about 80%, from names 62%, the page default 24%).
