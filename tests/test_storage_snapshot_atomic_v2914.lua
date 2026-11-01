-- P1: Storage snapshots are bounded and never report persistence success on failure.
DSP={settings={},market={state={sid=42}},
    lower=string.lower,
    clean_text=function(s)return tostring(s or '')end,
    trim=function(s)return tostring(s or ''):match('^%s*(.-)%s*$')end,
    item_key=function(s,n)return s..':'..tostring(n)end,
    flog=function()end}
local fail=false
DSP.save_settings=function()
    if fail=='throw' then error('io failure') end
    if fail then return false,'disk full' end
    return true
end
dofile('src/47_storage.lua')
local S=DSP.storage
for i=1,25 do
    local ok,why=S.accept('trunk','Багажник','Item x'..i,1000+i)
    assert(ok,why)
end
assert(#S.snapshots==20,'storage must retain exactly max_saved, not max_saved + 1')
assert(DSP.settings.storage_snapshots==S.snapshots,'persisted and live snapshot arrays diverged')
local old=S.snapshots
local signature=S.last_signature
fail=true
local ok,why=S.accept('trunk','Багажник','Item x999',5000)
assert(not ok and why:match('Не удалось сохранить'))
assert(S.snapshots==old and DSP.settings.storage_snapshots==old,'failed save mutated history')
assert(S.last_signature==signature,'failed save incorrectly deduplicated future successful observation')
fail='throw'
assert(not S.accept('trunk','Багажник','Item x1000',5001),'thrown save was ignored')
assert(S.snapshots==old,'thrown save removed previous snapshots')
fail=false
assert(S.accept('trunk','Багажник','Item x999',5002))
assert(#S.snapshots==20 and S.snapshots[1].rows[1].qty==999)
print('PASS storage snapshot retention, transaction rollback, failed/exceptional writes')
