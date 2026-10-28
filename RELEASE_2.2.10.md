# Palatka AI v2.2.10 RC — A-Z, storage TextDraw diagnosis, lightweight Carbon draw

**Base:** v2.2.9 full project. This is a source-level patch and a newly rebuilt CP1251 standalone, not a reskinned HTML demo.

## Changes

1. Arbitrage item groups are alphabetically ordered by default (case-insensitive CP1251, stable key tie-break). Toggle `А—Я` / `Прибыль: больше` in the arbitrage header; filtering and sorting use existing `V.memo` keyed by snapshot, query and sort mode. Finance and trade allocation are unchanged.
2. Storage has an **explicitly armed TextDraw diagnostic**. Tap `Начать сбор интерфейса`, open/close the native cabinet/trunk/warehouse, then tap `Завершить и разобрать`. `samp.events.onShowTextDraw` and `onTextDrawSetString` are hooked with previous handlers preserved. A 35-second capture is stored only in session memory, capped at 110 unique IDs; nothing is sent to a service or scanned continuously. TextDraw title must identify a container and item quantities must be explicit; when only a custom game UI exists, result truthfully reports that no parseable feed was seen. The parser does not guess remaining quantities or issue game actions.
3. Storage valuation/sort result is memoized per snapshot/mode/server/market version. Other-server appraisals stay disabled, unknown cost stays unknown, no inventory is moved/sorted in-game.
4. Optional Carbon DrawList row accents share native ImGui input/clipping, draw only visible virtualized rows, use a bounded max-shape budget and expose a settings switch. This is a **small native UI renderer step**, not an entirely new engine or native overlay interception.
5. Retain source modules, embedded 8028 PNG, presets, trade state, API/market logic, logs, 3D marker and mobile controls. No new networking or native `.so` modules.

## What is not solved / important limitations

- **A bespoke fullscreen game inventory UI can cover MonetLoader UI**. ImGui DrawList renders in MonetLoader's rendering layer and cannot force itself above a separate native UI layer. The capture workflow intentionally starts *before* opening the container and the analysis is viewed *after closing it*. Full data access requires inspecting actual packet types. Many native UI interfaces will emit no ordinary SA-MP dialog or TextDraw item data.
- No general native inventory scanner, no real in-game rearrangement or item disposal is implemented. No OCR/screen-recorder overlay is shipped. Don't pretend a screenshot proves the packet protocol.
- Real monetloader phone FPS, crash-free reload, UI visual fit and TextDraw packet capture are **unverified**; the old trade listing and API availability issues are not declared fixed.
- Market estimated liquidation value is not net profit and does not include unknown acquisition costs.

## Local test method

`python3 build.py` rebuilds the autonomous file, validates CP1251 syntax through texlua fallback. All `tests/test_*.lua` are run with `texlua` with per-case exit codes; full `python3 run_tests.py` requires LuaJIT, not installed. Specific new tests: `test_v2210_group_sort.lua`, `test_v2210_storage_textdraw.lua`, `test_v2210_draw.lua`.

## Native verification request, no transactions

1. Run `/crr`, select **Хранилища**, tap `Начать сбор интерфейса`.
2. Close Palatka AI (or return to game), open a trunk, wait for contents, close the trunk; return to **Хранилища**, select `Завершить и разобрать`.
3. Send the reported **TextDraw event count**, result/error, client type, screenshot of open native container and relevant `standalone.log` lines (redact nick and other private data). A zero count means this channel isn't reaching the Lua hook, not that trunk is empty.
4. Check **Арбитраж** default А-Я and toggle sorting to profits, and settings switch for Carbon DrawList. Compare game FPS/memory with the switch on/off during the same view, not during purchases/sales.
