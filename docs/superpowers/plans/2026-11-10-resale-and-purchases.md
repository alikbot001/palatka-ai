# Resale, demand evidence and purchase notes

**Goal:** Add a market-underpricing mode and durable purchase notes to native MCR arbitrage; replace horizontal pagination with vertical scrolling.

**Constraints:** Original MCR style/window size; no token, new dependency or automatic trades. Asking prices and buy orders are not proven purchases. Preserve server/currency/item/variant identity, integer monetary safety and existing trade guards. User has already requested autonomous implementation without confirmation loops.

## Design and contracts

- Tabs: Маршруты / Перепродажа / Закупки. Header and navigation/summary remain outside a vertically scrolling body. Clip off-screen route rows using known row geometry rather than rendering thousands every frame. No left/right page controls.
- Resale reference: median of lowest asking price per independent peer owner/shop, excluding the candidate merchant; at least three peers, fresh/current-server/exact ID+variant+currency only. Undercut reference by 1%, estimate net after configured commission, default minimum ROI 10%, maximum 10 units per item, shared configured budget. Orders/sales evidence affects ranking; default excludes unknown demand.
- Demand evidence: current independent buyers and declared quantities at prices >= candidate purchase price; OR at least 3 user-recorded sales / 20 units in last 7 days. Names explicitly distinguish current buy orders, the user's recorded sales and unknown market sale speed. Never infer a sale from a disappearing listing or count sellers as actual buyers.
- Purchases: independent `purchases.json`; manual lots with name, optional exact item identity, server/currency, unit cost, qty, date and note. Optional partial sale records take actual total received, not estimated revenue. Preserve remaining quantity, acquisition cost and recorded realized profit; manual-only names never match ambiguous market identities. Failed/corrupt reads block writes; saving publishes a new state only after atomic host write succeeds.

### 1. Pure resale model (worker)
Files: `mcr_copy/src/resale.lua`, `mcr_copy/tests/test_resale.lua` only.
Factory: `return function(E) return R end`.
`R.rank(state,server,now,options,yield_fn) -> rows,error`.
Options: currency (required), ttl=3600, tax_bp=200, budget=0, min_roi_bp=1000,
max_qty=10, min_peers=3, undercut_bp=100, popular_only=true, own_sales={key={events,qty,last_at}}.
Rows extend route-like fields: id,variant,name,currency,qty,seller,seller_qty,buy_price,
sell_price (estimated target),reference_price,peer_count,cost,gross,fee,net,profit,roi_bp,
popularity={kind,buyer_shops,buyer_qty,own_events,own_qty}. No buyer shop is fabricated.
- [x] Tests RED then GREEN: 10–13k vs 15–17k example, demand/own sales gates, outliers,
  duplicates/same merchant, expiry/future/server/variant/currency, shared budget/stock,
  fees/ROI boundaries, insufficient peers, unknown demand and overflow/cancellation yields.

### 2. Pure purchase ledger (worker)
Files: `mcr_copy/src/purchases.lua`, `mcr_copy/tests/test_purchases.lua` only.
Factory: `return function(E) return P end`.
`P.new() -> state`; `P.validate(pack) -> state,error`;
`P.buy(state,{server,currency,name,item_id?,variant?,unit_cost,qty,at,note?}) -> next_state,lot_or_error`;
`P.sell(state,lot_id,{qty,net_total,at,note?}) -> next_state,sale_or_error`;
`P.view(state,server,currency) -> {lots, invested, realized_profit, sold_qty}`;
`P.evidence(state,server,currency,now) -> {[engine_item_key]={events,qty,last_at}}` (last 7 days, exact identity only).
State schema1, next_id, lots, sales. Lot: id,server,currency,name,item_id?,variant?,unit_cost,qty,remaining,at,note.
Sale: id,lot_id,qty,net_total,cost,profit,at,note. Return new state, never mutate old state.
- [x] Tests RED then GREEN: partial sales, real net proceeds, free vs missing cost,
  server/currency/variant isolation, no oversale/overflow, corrupt/sparse packs, capacity,
  immutable failed operations, roundtrip validation and recent own-sale evidence.

### 3. Runtime/storage integration (root)
Files: new `workspace.lua`, tests, `host.lua`, builders.
Extend A with resale calculations outside frame, generation/server/revision checks and
current fresh results. Extend load and compute without changing app's existing contract.
Book operations run via host.run; read/parse errors retain/block ledger, writes serialize
candidate state and update only on success. Cache current-server book view outside frame.
- [x] RED/GREEN queued async tests: cancellation, late servers, write/read/encode failures,
  purchase after restart, no per-frame I/O and busy duplicate click.

### 4. Native UI and vertical lists (root)
Files: `ui.lua`, new `workspace_ui.lua`/`purchases_ui.lua`, strict UI tests/geometry.
Share original helper functions, use confirmed mimgui exports only. Fixed-size clipped
list rows; full long names/details in selected item. Tabs, refresh, settings and source
controls retain MCR style. Book forms have bounded scrolling bodies and explicit save
state; input price/quantity validation must not silently reuse a prior valid number.
- [x] RED/GREEN tests for tabs, vertical scroll without page buttons, row selection,
  visible popularity/reference/ROI provenance, purchase/sale forms and stale action guards.
- [x] Geometry: 800x360/925x512/1120x650/phone dimensions, long names, 5000 rows,
  popup scrolling and no footer overlap. Native screenshots if a device is available.

### 5. Integration, review and candidate publication (root)
- [x] Read worker diffs and test evidence; independent review of calculations/storage/UI.
- [x] Full targeted verification + generated CP1251 compilation, final artifact updater/SHA pipeline.
- [x] Build local.10, document limits, update candidate PR/tag/channel only, verify remote bytes
  and CDN status honestly. Never promote main/stable or claim phone acceptance without evidence.

Final verification: 24 Lua suites, 13 Python tests and CP1251 bytecode build exit 0; 126 geometry cases and 5000-row virtual list. Live-input probe accepted 97 shop snapshots and 86 uniquely mapped monthly statistics, produced 13 estimates within 100M budget; no trades. Independent review fixes: queued busy cleanup, same-window popup routing, source SID capture, immutable ledger load-revision guard, strict sale payload and SA$ source scope.

Native status: existing phone file was local.9, backed up to Download/PalatkaMCR-backup-20261110/palatka_before_local10.lua. local.10 file staged/hash-verified and renamed; chat was not opened, no command typed. User requested GitHub-only download handoff, so further phone interaction stopped. File hash 556d244a00c976793f15264a07fbd35c774a52ded435a9ca81a68e8aebaec54b. Native acceptance remains pending.
