local play = dofile("hook_play.lua")
local function press(field, v)
  for _, p in pairs(manager.machine.ioport.ports) do
    for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
  end
end
-- one piece per 60 frames from 1150: shift k steps (k = piece mod 7: 0..3 left, 4..6 right), then hold down
return function(n)
  if n < 1100 then play(n) end
  if n >= 1150 then
    local t = (n - 1150) % 60; local piece = (n - 1150) // 60; local k = piece % 7
    local dir = (k < 4) and "P1 Left" or "P1 Right"; local steps = (k < 4) and k or (k - 3)
    press("P1 Left", 0); press("P1 Right", 0); press("P1 Down", 0)
    if t < steps * 6 and (t % 6) < 3 then press(dir, 1) end
    if t >= 24 and t < 54 then press("P1 Down", 1) end
  end
end
