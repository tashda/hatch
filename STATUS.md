# Hatch: build status

Updated whenever work lands. "Verified" means it was compiled and its tests were run. This file is the source of truth for what exists.

## Environment facts

- The cloud session is Ubuntu 24.04 x86_64, **no macOS, no SwiftUI/AppKit**. Swift 6.1.3 for Linux is installed with `tools/install-swift-linux.sh` (Docker Hub image layers; download.swift.org is blocked).
- This session can only reach `tashda/echo` on GitHub and cannot create repositories. Work lives under `Hatch/` on branch `claude/echo-labs-features-wmwnbv`. It is laid out so it can move to its own repo with history (`git subtree split --prefix=Hatch`).
- Echo's CI runs on a self-hosted macOS runner (`xcode-27`). It is the only route to compile SwiftUI code from a cloud session.

## Built and verified (Linux, Swift 6.1, `swift test`)

- **HatchCore**: SQLite wrapper with FTS5, schema v1 with migrations, the 16-status workflow with who-may-move-what rules, ticket store (create, move, resume, change type, edit with original kept, themes), events, notes, questions, links, attachments, similar-ticket and Spec search, sync queue with coalescing and backoff, file claims (queue, stack, wake on release), agent queue and slots (`take`), Proposal state (picks, verdicts, pins, revisions), decisions, agent runs. 32 tests pass.

## Built, not verified

(nothing yet)

## Not started

Everything in `SUMMARY.md` section 8.
