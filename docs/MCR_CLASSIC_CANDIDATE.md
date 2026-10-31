# Palatka AI — MCR Classic UI (candidate, 31.10.2026)

## Scope

Original MCR-inspired layout, not the legacy MCR script nor a binary transplant.
The Palatka AI engines, live scanners, shop cache, market API, preset models,
safe trade queues, confirmation modal, and cash journal remain authoritative.

- Optional shell `src/69_mcr_classic.lua` (default for settings without a UI style),
  with warm native mimgui buttons, a narrow scrolling left navigation rail,
  separate inventory/catalog and current preset lists, and a fixed right-side
  action rail with sale/buy, inventory scan, preset library, launch and stop.
- Existing trade validation, actual inventory limits, dry_run and launch
  confirmation remain in `src/61_ui21_trade.lua`.
- Tap a prepared item to open a popup for price, amount, enable/disable, remove.
- Existing `src/60_ui21_shell.lua` remains available via the `Наш UI`
  action, and returns to the MCR layout through `MCR` in its footer.
- `src/56_mini_journal.lua` is now a compact, low-opacity journal,
  anchored after drag without a mandatory pin operation.
  Position persists via existing `C.drag/end_drag` logic.
- The full journal controls opacity, touch-through, compact vs expanded mode.
  When touch-through is on, switch it off from the full journal screen.

## Safety, limitations and rollout

- No MCR authentication, anti-tamper, binary, automation or network code copied.
- No extra game packets are sent by this UI. Listing still uses Palatka's
  existing validated queue and requires explicit confirmation.
- Full compatibility with MonetLoader on Android and visual parity with the
  2023–24 MCR UI have **not been demonstrated**.
- MCR-like user experience is implemented independently; this is not
  a byte-identical reproduction.
- Do not publish an OTA/main release without Android touch, DPI, rotation and
  sale/buy tests. This branch is a review candidate only.

## Manual smoke checks on a real Android device

1. Open the interface on 800×360, 925×512 and 1120×650. Verify drag, resize,
   close and switching between MCR and Palatka without full-screen takeover.
2. In Sale and Buy, add from inventory/catalog and edit price/qty.
   Enter invalid values and verify the queue does not launch.
3. Open preview/confirmation and test dry-run before a real stall attempt.
4. Verify receipt amounts, budget, taxes and trade journal against the game.
5. Drag the mini-log, reload, and confirm the saved anchor.
   Toggle opacity, click-through and compact/full modes.
6. Verify no added FPS stalls and no regression in the scanners, cache,
   arbitrage, pawnshop or inventory storage.

## Technical notes

`build.py` includes `69_mcr_classic.lua` after all Palatka UI modules and
before `99_main.lua`. The installed `imgui.OnFrame` dispatcher calls the
current `DSP.ui.draw` at runtime, so the style can be switched without
reinstalling callbacks. `DSP.ui22` and `DSP.ui21` share the same view model.

This file describes an unverified feature candidate. Do not report it as
tested or released on Android until the above acceptance checks pass.
