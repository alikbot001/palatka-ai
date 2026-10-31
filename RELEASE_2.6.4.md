# Palatka AI — v2.6.4 legible WebUI (candidate)

## Scope
- Restore Russian UI labels in UTF-8 source modules that had been stored as CP1251 mojibake (for example `Òîðãîâëÿ` instead of `Торговля`).
- Fix the nested UTF-8 mojibake trunk title `Последний открытый багажник`.
- Reorder the native ImGui navigation around common tasks: trading, shop, arbitrage, storages, journal.
- Increase native ImGui font target and sidebar width, preserving the current trading/runtime logic.
- Adapt floating WebUI to phone-sized viewport widths up to 1060 CSS px: simplified title, readable labels, 44 px controls, bottom navigation, compact landscape spacing, improved contrast.
- Refresh the WebUI HTML cache version; update overlay manifest and package byte sizes.
- Add `/crhide`, `/crweb`, `/crlegacy`, `/crresetui`, `/crversion` escape commands in the in-game chat (when chat command registration is available).
- Keep WebView hidden when its host geometry cannot be positioned/sized; retain cached HTML on HTTP failure and back up the previous file during replacement.
- Add `python3 tools/check_ui_text.py` as a source/manifest sanity check.

## Deployment and limitations
This is a **candidate branch**, not an installed Android build. Do **not** claim native validation, reliable WebView geometry on MonetLoader, or successful network updater installation. Rebuild the standalone CP1251 Lua from source before testing native ImGui text changes; the already committed `palatka_ai.lua` has **not** been regenerated. The WebUI bootstrap/HTML use separate update assets; their manifest sizes were synchronized for subsequent publication. Do not confuse these two deployment paths.

## Verification
Static review of the accessible GitHub source showed corrected Russian navigation labels and no remaining long Latin-1 mojibake runs in the reviewed source modules. The source guard was added but **not executed** in a real repository checkout in this session. Neither `build.py`, `run_tests.py` nor MonetLoader were executed: this environment has no mounted GitHub checkout or Android device. The current update manifest metadata is based on the UTF-8 bytes of the changed files, not a real device download.

For a developer checkout on Arch Linux:
```bash
python3 tools/check_ui_text.py
python3 build.py
python3 run_tests.py
```
Then check in MonetLoader: font sizes and Russian text in old/native UI, floating WebUI dimensions at portrait/landscape, normal `/crr` toggle, rescue commands, network interruption, and state preservation.

User data (presets, logs, settings, stored prices) must not be deleted during UI changes.
