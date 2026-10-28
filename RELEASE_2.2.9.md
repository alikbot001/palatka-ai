# Palatka AI v2.2.9 — Native Carbon Trade layout and storage inventory (RC)

**Baseline:** `Palatka_AI_v2.2.8_FULL.zip`. Edited UTF-8 `src/*.lua`, rebuilt CP1251 `palatka_ai.lua` with `python3 build.py`, retained full standalone indexed image bank. Market Helper is neither included nor a dependency.

## Native UI, not a browser layer

Changed `60_ui21_shell.lua` and added `60a_carbon_home.lua`, `60b_carbon_storage.lua`. The Carbon Trade 02 design is no longer only a color palette:
- actual main/home dashboard; native top brand/version/server line, manually triggered refresh, a persistent left navigation column for wide views, collapsible drawer on narrow views, integrated narrow lower status bar;
- shortcut cards, 2×2 separate metric panels, last session events, direct navigation to the preexisting trade/shops/scan/market/arbitrage/resale/promo/journal/history/statistics/calculator/notes/settings modules;
- virtualized navigation and fixed ▲/▼ buttons; existing per-screen lists, dialogs, user data and icons remain intact.

Browser CSS, fonts, shadows and window structure cannot be copied literally into mimgui. Visual pixel-equivalence is **not** established. Screens for trading/analytics retain their existing inner layouts; this update fundamentally changes the window *shell* and dashboard, but doesn't rewrite every internal form.

## Storage analyzer (`47_storage.lua`)

- Read-only observation of ordinary SA-MP text dialogs whose titles clearly identify a trunk, cabinet or warehouse. The existing `DSP.live.on_dialog` passes these events to the parser, preserving prior event hooks.
- Snapshot stores item names, per-row observed quantities (explicit units only), source (`dialog` or `manual`), server and timestamp. A repeated callback within three seconds doesn't double counts. At most eight snapshots and 180 lines per snapshot; saved in existing settings.
- Sorted preview by estimated liquidation value, quantity, unit buy-price, category or name. Values are based on the *current server's* market **buyer offers**; separate asking-price totals are not actual realizable sales. Missing prices and missing quantities are shown explicitly. Other-server snapshots never inherit local market quotes.
- Manual text entry fallback for custom interfaces with one item per line. Requires a clearly marked source (`manual`); no claim of direct observation.
- Clear snapshots uses an actual confirmation modal; on settings-write failure, previously held snapshots are restored. No game inventory actions, item movement, purchases or memory scraping.

**Limits:** Arizona announced that its new built-in inventory sorter is on the **updated PC inventory**. Custom mobile containers may use textdraws or bespoke packet formats, not classic `onShowDialog`, so automatic recognition must be checked with an Android capture before a native PASS is assigned. A container's appraised value is not profit without cost basis.

## Verification performed

- `python3 build.py` — exit 0, resulting CP1251 source syntax accepted by `texlua`.
- `texlua tests/test_v229_storage.lua` — PASS: 45,000 units vs unknown, valuation, duplicate callbacks, cross-server quote protection, manual provenance, unrelated-dialog filtering.
- `texlua tests/test_v229_home_model.lua` — PASS: dashboard buttons, navigation, refresh only after click, non-generated financial counters.
- `texlua tests/test_standalone.lua` — PASS: loader fixture, embedded catalog and PNG read.
- `texlua tests/test_v224_version.lua` — PASS: version metadata aligned.
- Full loop `texlua tests/test_*.lua` — 63/72 exit 0. Nine tests cannot run on this runtime: eight depend on LuaJIT `bit`/FFI and one contains LuaJIT-specific integer-literal syntax. This does **not** mean they pass.
- `python3 run_tests.py` — exit 1 **before tests**, missing LuaJIT.
- `python3 tools/verify_embedded_icon_bank.py` — 8028/8028 SHA-256 and offset checks PASS.
- No MonetLoader/Android device, no real container packet capture, no actual browser-to-mimgui pixel comparison. No purchase/sale/item move was performed.

## Requested native check (no trading actions)

1. Install the standalone Lua, open `/crr` on the Galaxy A15, inspect the sidebar and main dashboard in landscape. Open the trading, arbitrage, market, journal and storage views. Screenshot any clipping of the top bar, row buttons or lower footer.
2. Open a trunk and a home's cabinet, then `Хранилища`. If no observation appears, collect the MonetLoader log plus a screenshot of the **open interface** and note whether it is a classic SA-MP dialog or custom UI. The screenshot alone cannot establish an internal packet format.
3. With one item showing e.g. 45,000 units, verify item name, count, timestamps, and current-server price. Compare storage's *estimated sale-to-buyers value* with market quotes; do not treat this as confirmed cash profit.
4. Reopen a container, change sort mode, restart script and check saved snapshots. The UI sort only changes this script's display, not the actual game inventory order.

**Remaining work:** native visual acceptance of all tabs/menus, custom-container packet support, and existing trade queue/API reliability issues from v2.2.8 still require device-specific logs and testing; this patch does not claim to resolve those separate issues.
