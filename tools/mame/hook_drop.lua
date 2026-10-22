local play = dofile("hook_play.lua")
local function press(field, v)
  for _, p in pairs(manager.machine.ioport.ports) do
    for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
  end
end
local cnt, last = 0, 0
return function(n)
  if n < 1100 then play(n) end
  if n == 2 then
    local sp = manager.machine.devices[":gaelco_ds5002fp"].spaces["hostmem"]
    TAPM = sp:install_write_tap(0x0000, 0xffff, "mw", function(o, d, m) cnt = cnt + 1 end)
  end
  if n >= 1150 then press("P1 Down", (((n - 1150) // 30) % 2 == 0 and n < 1750) and 1 or 0) end
  if n % 20 == 0 and n >= 1100 then
    if cnt ~= last then print("MAME frame", n, "mcu_hostwr", cnt, "+", cnt - last) end
    last = cnt
  end
end
