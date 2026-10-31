# Palatka AI: scan inventory / cabinet / warehouse — implementation plan

## Scope and known facts (2026-10-31)

- The native Android game can render containers without SA-MP dialog or TextDraw events.
- Confirmed in this project from a previous real capture: packet 220, marker 84, iface 52, sub 0, JSON `type=8`, item batches across 180 slots: **vehicle trunk**.
- `src/47_storage.lua` already consumes complete trunk batches, rejects unidentified deltas, and retains the last fully observed trunk. Preserve that logic.
- The exact type, capacity, source ID and batch format for **personal inventory, house cabinet and warehouse** have **not** been verified. Source notes describing them are hypotheses, not raw captures. Never map by guess.

## Phase A — implemented on feature branch

Files:
- `src/47b_storage_probe.lua`: opt-in observer, max 60 seconds, 180 slots per candidate, eight candidates, 100 KB input cap, only iface 52 sub 0/2; excludes confirmed trunk type 8 and stall inventory type 1/sub 2; no outgoing packets, no raw chat/password capture. Explicit local `storage_probe_report.json` export contains only metadata (type, sub, slot/packet counts), never inventory item IDs or names.
- `src/45_live.lua`: forwards iface 52 payloads to observer via protected call, then executes the existing trunk/trade handlers unchanged.
- `src/60e_storage_probe_ui.lua` and `src/60b_carbon_storage.lua`: native mimgui controls inside Storage > Scan.
- `build.py`: include both modules in the standalone build.
- `tests/test_v250_storage_probe.lua`, `tests/test_v250_storage_probe_ui.lua`: pure Lua model tests.

Usage: Storage > Scan > choose inventory/cabinet/warehouse > start 40s > close Palatka > open only the chosen container in game > reopen Palatka > stop > view candidates. Saving requires a separate click. An optional **Create safe report** button writes `PalatkaAI/storage_probe_report.json` locally; it is never uploaded automatically. Every candidate is **unverified / potentially partial**; the displayed type is a packet type, not a proven container category. User-provided container label is not a trustworthy protocol identity. Unknown item count stays unknown. Never mix sub 0/2 and never merge trunk type 8 into other views. The save contains a local snapshot only; no packets leave the device.

No screen scraping, injected clicks, gameplay automation, network requests, authentication or remote upload.

## Phase B — needed before promising automatic full scans

1. Run separate capture windows for: own inventory, one home cabinet, one warehouse, one trunk control.
2. For each, compare packet types, sub IDs, batch sequencing, declared capacity and any *verified* stable container ID. Request only sanitized metadata + 1-2 syntheticized item entries, not raw account or other players' data.
3. Establish a binding of `type/sub` to a container class from at least two independent captures; do not infer class solely from timing or nearby shop activity.
4. Build a typed reader with exact fields and declared capacity, strict slot validation and fresh complete-batch session. Never apply partial updates without matching verified container identity.
5. Make the live snapshot show a clear completeness state: full / partial / unknown; values only for the confirmed observed slots. Reuse existing valuation and sorting.
6. Compare on phone: visible item names, enchant, quantities, empty slots, containers with 0 items; test opening two different containers in succession.

## Phase C — release gates

- `python3 build.py` and `python3 run_tests.py` with LuaJIT. New pure Lua tests should pass.
- MonetLoader x64 tests: packet observer never prevents normal inventory/shop/trunk UI; no freezes, no incorrect auto-snapshot, no duplicate saves; game tick/FPS unaffected when observer disabled.
- Stale/corrupt/malformed/oversized packets ignored; saving failure restores previous snapshot; per-server snapshots and raw logs remain private.
- Do not publish into main/OTA until Android acceptance. Keep current 2.5.2 normal mimgui distribution available.
- Review existing `build.py` manifest discrepancy with source tree separately, before any commercial release.
