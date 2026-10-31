-- Verify each detailed search result is tappable and drills into its item.
local messages,clicked={},false
DSP={
 ui21={storage_tab='library',storage_library_page='list',font_pixels=18},
 mobile={},
 lower=function(x)return string.lower(tostring(x or ''))end,
 trim=function(x)return tostring(x or ''):match('^%s*(.-)%s*$')end,
 money=function(x)return'$'..tostring(x or 0)end,
 storage={
  snapshots={},
  library=function()return{{snapshot={title='LRC',rows={}},index=1}}end,
  search_library=function(q)
    assert(q=='супер')
    return{storage_count=1,known_qty=30,unknown_slots=0,priced_value=3000,
      unpriced_groups=0,different_server=0,
      results={{index=1,snapshot={title='LRC',kind='trunk'},
       matched_items={{name='Суперларец',key='id:55:0',qty=30,unknown_slots=0,
                       total_buy=3000,unit_buy=100}}}}
    }
  end
 }
}
local V=DSP.ui21
function V.button()return false end
function V.heading(title,callback)if callback then callback()end end
function V.text(s)messages[#messages+1]=s end
function V.muted(s)messages[#messages+1]=s end
function V.green(s)messages[#messages+1]=s end
function V.red(s)messages[#messages+1]=s end
function V.fit(s)return s end
function V.apply_font()end
function V.inline()end
function V.reset_list()end
function V.search()return 'супер' end
function V.row(id,height,callback)callback(360,0,0)end
function V.at()end
function V.text_button()return false end
function V.list_rows(name,rows,height,callback)
 assert(name=='storage_search_results' and #rows==1)
 callback(rows[1],1)
end
imgui={
 Separator=function()end,
 GetContentRegionAvail=function()return{x=390}end,
 ImVec2=function(x,y)return{x=x,y=y}end,
 InvisibleButton=function()return clicked end
}
dofile('src/60b_carbon_storage.lua')
V.storage_screen()
assert(V.storage_library_page=='list')
assert(table.concat(messages,' | '):find('Количество: 30 шт.',1,true))
assert(table.concat(messages,' | '):find('3',1,true))
clicked=true
V.storage_screen()
assert(V.storage_library_page=='detail')
assert(V.storage_selected==1)
assert(V.storage_detail_key=='id:55:0')
print('PASS detailed storage UI: per-trunk quantity, valuation and full-row drilldown')
