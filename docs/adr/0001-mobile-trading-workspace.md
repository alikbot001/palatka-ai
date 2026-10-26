# Mobile trading workspace

Status: Accepted for implementation; device rendering requires the integration smoke run.

Context: The target Samsung A15 uses 2340x1080 landscape. Eight horizontal tabs and nine-column market tables clip text and leave small touch targets. Trading prices can exceed signed 32-bit integer input limits. The bottom game interaction strip must remain accessible.

Decision: Keep existing public screen identifiers and backend modules. Load five small UI modules after the existing UI dispatcher. Use a scrollable sidebar, a window occupying 94% width and 82% height at 3% from the top, wrapped item cards, 72px touch buttons, and persistent decimal text buffers for numeric edits. Always describe buying and selling from the player's perspective. Keep the two preset libraries distinct. Present arbitrage as a route with cost, net profit, quantity, freshness and separate shop markers. Page persisted reward history through the rewards API; unknown prices remain explicit. Store separate searchable notes with pinning and optional item/shop references in settings.notes; migrate the former text notebook once.

Consequences: No new dependency or transport is required. Existing configuration and commands retain compatibility. Lists scroll vertically and use explicit paging rather than wide tables. Each note editor is limited to 8191 UTF8 bytes, while total notes are unrestricted. Keyboard behavior and actual device typography remain part of the phone smoke run, beyond LuaJIT mock verification.
