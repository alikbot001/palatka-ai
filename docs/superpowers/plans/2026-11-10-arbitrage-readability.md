# Calm native arbitrage layout

**Goal:** Make the item, purchase shop, buyback shop and financial result easy to associate on a phone, retaining the original MCR shell and style.

**User constraints:** Native MCR appearance; no larger main window; clear trading context; no repeated confirmation prompts. Existing implementation is the design target.

**Design:** A short header identifies the screen/server. The body scrolls independently. Each list entry groups its item, ID/modification, separately labelled buy/sell quotes, planned quantity and estimated profit with one full-width details button. One or two entries per page according to available height. Details have explicit Buy → Buyback → Calculation sections. Footer keeps pagination or selected-route profit visible. Source/age remains attached to each shop in details; settings and sources stay in the native right sidebar.

**Files:** `mcr_copy/src/ui.lua`, `mcr_copy/tests/test_ui.lua`, a strict geometry harness under `mcr_copy/tests/`, builder/version, generated candidate artifacts and documentation. No changes to engine, market data or saved settings.

1. [x] Add failing assertions for item-associated entry order, independent scrolling, fixed footer and correctly labelled financial/stock values.
2. [x] Implement compact list and structured details using confirmed mobile APIs; keep tracking guards and centered popups.
3. [x] Exercise narrow/wide landscape geometry with wrapped long names, large amounts, empty/loading states and drag-click prevention. These are desktop models, not native screenshots.
4. [x] Run the targeted suite and builder; review diff for financial semantics, stale actions and per-frame work.
5. [x] Publish separate local.9 candidate and matching updater manifest, verify downloaded bytes; leave native acceptance explicitly pending if ADB is unavailable.

**Verification limits:** Desktop tests cannot prove Android typography, native rendering or actual touch behaviour. No live trades. Main/stable are not promoted.

Verification: `python3 mcr_copy/verify.py` — 13 Lua suites, 13 Python tests and bytecode build exit 0. The geometry model covers 72 layouts; ADB inventory is empty. Diff reviewed for native API compatibility, wrapping, stale-route guards and financial labels.

Published source commit `e5afe4d`, immutable tag `mcr-local.9`, draft PR #26 updated. Downloaded tag artifact equals local bytes: 2,105,456 bytes, SHA256 `a524326f9945b41c1cbc106845feb9a644b93acaf0ff4a9976dc28936b77a109`. GitHub API confirms channel manifest build 9, blob `40aaae6845b34dccae8115045a5385463f649732`, identical to local. Final-artifact LuaJIT SHA256/compile/updater pipeline passed with 129 yields.

CDN observation at 12:15 UTC: mutable raw manifest still returns cached local.8 (HIT, max-age=300, expires 12:19:47 UTC), including Cache-Control:no-cache request. This is not a verified live local.9 OTA response. Use the verified tag download immediately or retry /crrupdate after cache propagation. No Android installation/acceptance; ADB empty.
