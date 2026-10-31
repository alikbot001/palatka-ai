# Palatka AI — Arbitrage Session Agent candidate (31 Oct 2026)

This is an **optional** many-deal assistant attached to the native MCR Classic /
Palatka mimgui interface. It never submits purchases, sales or network packets.

## Flow

1. Open Arbitrage and tap **НАЧАТЬ СЕССИЮ**. The prepared, non-overlapping API
   route set is enqueued, limited to 24 *active* routes per review.
2. Or open a specific Best Plan / confirmed-local-quantity route and tap
   **В МИНИ-АГЕНТ**. Both sources share one queue.
3. A movable side window shows the next shop, item, price, amount, and
   quoted potential profit; **Найти лавку** uses Palatka's existing marker.
4. After an actual purchase, tap **КУПЛЕНО**, optionally adjusting quantity.
   After actual resale, tap **ПРОДАНО**, again with partial quantity support.
   The same execution cannot be counted twice beyond planned quantity.
5. The local execution ledger immediately reduces the matching *quote* amount
   by side, server, owner, price, item identity and source timestamp. This
   affects both API arbitration and local saved-shop routes. It never rewrites
   the API response or the original snapshot.
6. A confirmed completed route is removed from the active queue but remains
   accessible in the paged history. Skipped routes can be reopened.
7. The side window reviews currently available, already prepared market
   results at most once every 60 seconds, adding new candidate routes without
   replaying confirmed ones. **This is not a promise of 60-second HTTP polling**:
   `DSP.market.should_refresh` applies its independent 180-second minimum,
   backoff and existing game connection rules.
8. A uniquely matching purchase/sale system message can generate a **receipt
   suggestion**, never an unverified automatic execution or revenue entry.
9. The quote ledger is cleared logically for the next 05:00 server-day cycle.
   The execution history stays in `arb_agent_v1.json`.

## Important financial distinctions

The assistant's *done* count is the count of fully **user-confirmed** routes.
It is not automatically certified by the game server.

`profit_estimate` is calculated from quoted buy/sell prices and estimated
sale commission, scaled by confirmed sold quantity. It is **not actual audited
profit**. The pre-existing money/trade journal keeps recording real
recognized server messages independently; the agent does not log synthetic
cash entries there or count the same receipt twice.

If the packet / chat log contains no reliable quantity or shop identity,
automatic completion stays disabled. A receipt matching one unique pending
route shows a suggestion requiring user confirmation.

## Modules

- `src/69a_arbitrage_agent.lua`: model, local quote-consumption, persistence
  and guarded receipt suggestions.
- `src/69b_arbitrage_agent_ui.lua`: independent, movable and resizable side UI.
- `src/63_ui21_arbitrage.lua`: start full queue or add selected best plan.
- `src/63a_ui_local_arbitrage.lua`: add local known-quantity route.
- `src/46b_local_arbitrage.lua`: subtract confirmed locally consumed
  stock/demand instead of showing stale opportunities.
- `src/99_main.lua`: install read-only overlay.
- `tests/test_arbitrage_session.lua`: multi-route accounting and quote
  identity regression tests.

## Acceptance required before releasing

- Android MonetLoader/mimgui touch and screen-size check, including the
  small right-side window while gameplay remains interactive.
- Actual receipt samples: purchases, partial purchases, player-to-shop sales,
  own-stall sales. Unrecognized formats must not be auto-confirmed.
- Stale/changed owner, API refresh, 05:00 restart, server switch, fresh local
  shop scan and duplicate messages.
- Verify 100 bought / 100 sold one time, partial sales, multiple buyers for
  one item, equal quote prices, and restart/load persistence.
- Benchmark market review and ensure no stalls on an Android phone.

Status: review branch only. **No actual mobile execution has been validated.**
