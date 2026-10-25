package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return 'CP1251_ENC:' .. s end },
    UTF8 = {
      encode = function(self, s) return 'U8_ENC:' .. s end,
      decode = function(self, s) return 'U8_DEC:' .. s end,
    },
  }
end
getWorkingDirectory = function() return '/tmp/opencode/dsp_encoding' end
doesDirectoryExist = function() return true end
createDirectory = function() end
encodeJson = function() return '{}' end
decodeJson = function() return {} end
sampAddChatMessage = function() end
local f = assert(loadfile('src/00_core.lua')); f()
assert(DSP.to_cp('x') == 'U8_DEC:x', 'to_cp uses UTF8:decode: ' .. DSP.to_cp('x'))
assert(DSP.to_u8('y') == 'U8_ENC:y', 'to_u8 uses UTF8:encode: ' .. DSP.to_u8('y'))
assert(DSP.utf8('z') == 'U8_ENC:z', 'utf8 uses to_u8')
print('encoding tests: ok')
