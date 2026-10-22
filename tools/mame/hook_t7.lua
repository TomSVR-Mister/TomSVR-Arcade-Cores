local cur, t0, per, st = 0, 0, 1/59.1, {}
local function now() return manager.machine.time:as_double() end
return function(n)
  local t = now(); if t0 > 0 then per = t - t0 end; t0 = t; cur = n
  if n == 2 then
    local sp = manager.machine.devices[":maincpu"].spaces["program"]
    TAPKEEP = sp:install_write_tap(0x210000, 0x211fff, "pt", function(o, d, m)
      if cur >= 380 and cur <= 470 then
        local f = (now() - t0) / per; local r = st[cur]
        if not r then r = {n=0, a=f, b=f}; st[cur] = r end
        r.n = r.n + 1; r.b = f
      end
    end)
  end
  if n == 471 then
    for f = 380, 470 do local r = st[f]; if r then print(string.format("MAME after frame %d: writes %d from %.3f to %.3f frame", f, r.n, r.a, r.b)) end end
  end
end
