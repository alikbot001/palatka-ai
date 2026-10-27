local fixture=dofile('tests/test_v22_ui.lua').fixture
local h=fixture(1120,650)
DSP.items.by_id={[0]='   ',[1]='Wood',[2]='-', [3]='DELETED item'}
h.V.source='catalog';h:draw('palatka')
local rows=h.V.cache.items_rows.value
assert(#rows==1 and rows[1].id==1,'catalog must exclude blank and deleted names')
h.V.tab='preset';h:draw('palatka')
local labels={}
for _,r in ipairs(h.rects)do labels[r.label]=true end
assert(labels['Цена']and labels['Шт.'],'inline numbers need fixed column labels')
print('v22 native catalog findings: OK')
