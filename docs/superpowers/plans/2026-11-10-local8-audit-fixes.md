# Palatka local.8 audit fixes implementation plan

> **For agentic workers:** Use superpowers:executing-plans or subagent-driven-development. Track each verified step below.

**Goal:** Fix the seven reproduced local.7 regressions and bound UID discovery without fabricating licensing or game readiness.

**Architecture:** Keep immutable vendor code unchanged. Correct targeted builder transformations and local adapters; test extracted native functions with their actual string table. Preserve inventory ownership and acknowledgement checks.

**Tech Stack:** Python builder, LuaJIT, MonetLoader/mimgui; no new dependencies.

**Spec:** User-authorized fixes following the read-only audit of commit `9a3cabd`; reproduction scripts in `/tmp/palatka-local7-*-repro.lua` and `/tmp/palatka-enhanced-price-audit.lua`.

## Global constraints

- Preserve settings, presets, native controls, CP1251 output and attribution.
- No fake key, UID, entitlement or successful cloud response.
- Never execute real trades during verification; fake game ACKs only.
- Candidate channel only; no automatic stable promotion.
- Do not claim Android acceptance without connected-device evidence.

## Review focus

- Sell versus buy refresh must invoke the correct native branch (Task 1).
- Missing or delayed stats must not produce a ready trading state (Task 4).
- Same-name and enhanced items must retain ID/variant/currency identity (Task 5).
- Old callbacks, including same-server queries, must never change a newer view (Task 6).
- Buy flags becoming active during download must prevent installation (Task 7).

### Task 1: Restore native sell refresh (root)
**Files:** `build_mcr_local.py`, `mcr_copy/tests/test_local_build.py`.
**Interface:** `lIl_IIII()` dispatches `O3 == F3.sell` to `lI_I___l(true)`; buy refresh calls offline `lI_IlIII()` and preserves manual catalogue entries.
- [x] Add extracted-function assertions for sell and buy counters; run and observe failure.
- [x] Preserve native dispatch while replacing only remote buy catalogue handling.
- [x] Run Python local-build suite; confirm both branches and saved manual names.

### Task 2: Restore own Telegram settings (root)
**Files:** `build_mcr_local.py`, `mcr_copy/tests/test_local_build.py`.
**Interface:** Preserve `llIllIll()` and `SettingsUI.TelegramBot`; replace only `SettingsUI.TelegramMcrBot()`.
- [x] Add actual native-page harness asserting own-bot inputs and notification checkboxes are reachable; observe failure.
- [x] Remove whole-page replacement; keep unavailable MCR option explicit and disabled.
- [x] Verify own transport tests and full-settings save with empty MCR key.

### Task 3: Wall-time HTTP deadlines (root)
**Files:** `build_mcr_local.py`, `mcr_copy/src/elapsed.lua` if required, `mcr_copy/tests/test_local_build.py`.
**Interface:** Existing async HTTP signatures remain unchanged; deadline start/check share elapsed time source.
- [x] Inspect both native timer functions and available clock APIs; add low-CPU elapsed timeout harness and observe failure.
- [x] Replace CPU time only in HTTP deadline code using existing libc monotonic API; fail explicitly if the clock fails; preserve cancellation/failure delivery.
- [x] Verify timeout and successful response complete once, with no new dependency.

### Task 4: Bound UID discovery (root)
**Files:** `build_mcr_local.py`, `mcr_copy/tests/test_local_build.py`.
**Interface:** `lII____l()` returns after bounded discovery; unrecognized/missing stats retains `L6.isCheckUID` and false native readiness.
- [x] Inspect parser, retry loop and readiness consumers; add missing-stats and recognized-stats harnesses, observe unbounded failure.
- [x] Bound initial discovery to 30 elapsed seconds and at most 5 requests, report timeout once; retain genuine parser and trading guards.
- [x] Verify native main loop can proceed without granting readiness; successful stats remains usable.

### Task 5: Price identity and enhanced names (market worker)
**Files:** `mcr_copy/src/market.lua`, `mcr_copy/src/local_market_host.lua`, market Lua tests only.
**Interface:** Keep legacy name calls when unambiguous; expose and accept explicit ID/variant/currency selector for ambiguous names through native UI.
- [x] Reproduce native `Item(+4)` lookup and two IDs named `Череп`; correct inaccurate formatter mock.
- [x] Align name contract; show IDs/variants and provide an actual selectable identity path without combining groups.
- [x] Assert both identities resolve separately, including enhanced names and currencies.
- [x] Final review: preserve native `total_value` protocol with exact sums, reject overflow; test actual vendor consumer.
- [x] Final review: remembered selection must respect currency and permit explicit recovery after selected ID disappears.

### Task 6: Discard obsolete market callbacks (market worker)
**Files:** Same as Task 5.
**Interface:** Per-view generations cover generic read states and native `Y6` worker.
- [x] Add reversed completion tests across server changes and repeated same-server queries; observe failure.
- [x] Ignore outdated completions and workers without replacing newer success with errors.
- [x] Verify latest success/failure still propagates and views leave WAIT appropriately.

### Task 7: Guard updates during buys (updater worker)
**Files:** `mcr_copy/src/local_update_host.lua`, `mcr_copy/tests/test_update_host.lua`, updater-specific tests only.
**Interface:** `busy()` includes `m6` and `isParseInventoryDialogsForBuy`, checked before and after download by updater.
- [x] Add actual-adapter tests for each flag, both at invocation and after download; observe old-code failure.
- [x] Extend busy predicate without changing update/install protocol.
- [x] Verify no install while busy and normal update resumes when idle.

### Task 8: Integration and candidate delivery (root)
**Files:** version/build constants, `outputs/palatka_mcr_*`, README and audit evidence.
- [x] Read worker diffs and actual test outputs; inspect unresolved risks.
- [x] Run all dedicated Lua/Python suites and bytecode compilation; compare legacy test baseline if run.
- [x] Bump to local.8/build 8; build manifest and artifact together, verify size/SHA/version and CP1251.
- [x] Record verification and remaining native limitations, update plan checkboxes.
- [ ] Commit/push feature branch, immutable candidate tag, update PR #26 without merging stable.
- [x] Check ADB inventory; install only if safely accessible, otherwise explicitly report not installed.
