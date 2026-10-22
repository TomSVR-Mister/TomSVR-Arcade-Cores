local inner = dofile("hook_match.lua")
local cnt = 0
return function(n)
  inner(n)
  if n == 2 then
    local sp = manager.machine.devices[":gaelco_ds5002fp"].spaces["hostmem"]
    TAPM = sp:install_write_tap(0x0000, 0xffff, "mw", function(o, d, m) cnt = cnt + 1 end)
  end
  if n >= 1100 and n % 20 == 0 then print("M", n, cnt) end
end
