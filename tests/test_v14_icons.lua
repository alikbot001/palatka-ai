DSP={dir='/tmp/palatka_v14_image_test',mkdir_p=function(path) os.execute('mkdir -p '..path) end,flog=function(s) print(s) end}
assert(loadfile('src/08_icons.lua'))()
print('v1.4 icons extracted')
