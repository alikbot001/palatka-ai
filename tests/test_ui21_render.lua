-- Compatibility smoke uses the strict UI22 harness and retains all old screen IDs.
-- Missing ImGui APIs and V.errors now fail; a caught exception cannot print PASS.
assert(dofile('tests/test_v22_ui.lua'))
print('UI21 screen compatibility through strict UI22 harness: ok')
