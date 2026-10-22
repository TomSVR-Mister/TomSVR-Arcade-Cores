-- same inputs as ver/bangb/fast.cab (sim frame f = MAME frame f)
local function press(field, v)
  for _, p in pairs(manager.machine.ioport.ports) do
    for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
  end
end
local sp = manager.machine.devices[":maincpu"].spaces["program"]
blog = io.open("bfast2_mame.txt", "w")
local seq = { {250,256,"Coin 1"}, {280,286,"1 Player Start"}, {320,326,"1 Player Start"} }
for k = 0, 6 do seq[#seq+1] = {360+40*k, 366+40*k, "P1 Button 1"} end
return function(n)
  for _, s in ipairs(seq) do
    if n == s[1] then press(s[3], 1) end
    if n == s[2] then press(s[3], 0) end
  end
  blog:write(string.format("%d cnt=%d s1=%d ad7=%02x\n", n, sp:read_u16(0xfe29a8), sp:read_u16(0xfe29aa), sp:read_u8(0xfe2ad7)))
end
