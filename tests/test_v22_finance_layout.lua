local h=dofile('tests/test_v22_ui.lua').fixture(2340,1080)
h:draw('calculator')
for _,keys in ipairs({{'buy','sell'},{'qty','commission'}})do
 local left=h:find('v22_finance_'..keys[1]);local right=h:find('v22_finance_'..keys[2])
 assert(left and right,'both financial fields must render')
 assert(right.x>=left.x+left.w+4,'right financial input must stay under its own label')
 assert(math.abs(right.y-left.y)<1,'paired financial fields align')
end
print('v22 native finance field placement: OK')
