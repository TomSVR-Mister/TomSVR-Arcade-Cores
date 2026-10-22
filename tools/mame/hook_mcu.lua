local play = dofile("hook_play.lua")
local cur, cnt, rcnt = 0, 0, 0
return function(n)
  cur = n; play(n)
  if n == 2 then
    for _, tag in ipairs({":gaelco_ds5002fp", ":gaelco_ds5002fp:mcu"}) do
      local d = manager.machine.devices[tag]
      for nm, sp in pairs(d.spaces) do print("space", tag, nm) end
    end
    local sp = manager.machine.devices[":gaelco_ds5002fp"].spaces["hostmem"]
    TAPM = sp:install_write_tap(0x0000, 0xffff, "mw", function(o, d, m) cnt = cnt + 1 end)
    TAPR = sp:install_read_tap(0x0000, 0xffff, "mr", function(o, d, m) rcnt = rcnt + 1 end)
  end
  if n % 100 == 0 then print("MAME frame", n, "mcu_hostwr", cnt, "hostrd", rcnt) end
end
