-- Model the menu and popup confirmation with no Android UI dependencies.
package.loaded['ffi']={string=function(x)return tostring(x)end,copy=function()end}
local pressed,opened='',nil
local old={id='saved_1',title='LRC',source='packet220_trunk_named',kind='trunk'}
local newest={source='packet220_trunk',kind='trunk',slots_count=180,
 rows={{id=111,name='Item111',qty=2}},count_known=2,occupied_slots=1,observed_at=os.time()}
local trunk={snapshot=newest,status='saved',review_needed=true,review_generation=22,
 autoscan_enabled=true,received=180}
DSP={ui21={},mobile={},market={state={sid=1}},
 storage={snapshots={newest,old},
  trunk_state=function()return trunk end,
  match_saved_trunks=function(s)
    assert(s==newest)
    return{{id='saved_1',title='LRC',shared=1,similarity=50}}
  end,
  find_snapshot=function(id)
    if id=='saved_1' then return old,2 end
  end,
  apply_latest_to_saved=function(id)
    assert(id=='saved_1');trunk.review_needed=false;return true,old
  end,
  evaluate=function()return {sell_to_buyers=100,ask_value=120}end,
  library=function()return{{snapshot=old,index=2}}end,
 },
 money=tostring}
local V=DSP.ui21
V.font_pixels=18
function V.button(label,id)return pressed==id end
function V.text_button(label,id)return pressed==id end
function V.heading(title,cb) if cb then cb()end end
function V.text()end
function V.muted()end
function V.green()end
function V.red()end
function V.fit(s)return s end
function V.inline()end
function V.reset_list()end
function V.apply_font()end
function V.memo(key,sig,cb)return cb()end
function V.list(key,cb)cb(360)end
function V.list_rows()end
function V.open_popup(title,id)opened=id end
function V.popup(title,id,cb) if opened==id then cb() end end
imgui={Separator=function()end,
 GetContentRegionAvail=function()return{x=360}end,
 CloseCurrentPopup=function() opened=nil end,
 new={char=setmetatable({},{__index=function(_,n)return function()return '' end end})}}
dofile('src/60b_carbon_storage.lua')

V.storage_screen()
assert(opened=='storage_match_confirm','auto prompt must open after successful new scan')
assert(V.storage_match_review.matches[1].id=='saved_1')
pressed='storage_match_yes'
V.popups()
assert(trunk.review_needed==false,'confirmation must finalize review')
assert(V.storage_tab=='library' and V.storage_library_page=='detail')
assert(V.storage_selected==2 and opened==nil)

-- Another completed scan should lead to a new confirmation prompt.
trunk.review_needed=true;trunk.review_generation=23
V.storage_tab='scan';V.storage_library_page='list';pressed=''
V.storage_screen()
assert(opened=='storage_match_confirm')
pressed='storage_match_no_new';V.popups()
assert(V.storage_name_target==newest)
assert(opened=='storage_trunk_name','No means save as new, not overwriting')
assert(trunk.review_needed==false)
print('PASS storage matching modal: yes applies, no opens naming dialog')
