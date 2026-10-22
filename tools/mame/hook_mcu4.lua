local inner = dofile("hook_match.lua")
local cur = 0
local f = io.open("mame_acc.txt", "w")
return function(n)
  inner(n); cur = n
  if n == 2 then
    local sp = manager.machine.devices[":gaelco_ds5002fp"].spaces["hostmem"]
    TAPW = sp:install_write_tap(0x0000, 0xffff, "mw", function(o, d, m) if cur >= 1596 and cur <= 1625 then f:write(string.format("W %04x %02x\n", o, d)) end end)
    TAPR = sp:install_read_tap(0x0000, 0xffff, "mr", function(o, d, m) if cur >= 1596 and cur <= 1625 then f:write(string.format("R %04x %02x\n", o, d)) end end)
  end
  if n == 1626 then f:close() end
end
