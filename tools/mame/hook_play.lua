-- same inputs as game.cab (sim frame f = MAME frame f)
local function press(field, v)
  for _, p in pairs(manager.machine.ioport.ports) do
    for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
  end
end
local seq = { {600, 608, "Coin 1"}, {660, 668, "1 Player Start"}, {760, 790, "P1 Button 1"},
              {790, 830, "P1 Right"}, {830, 860, "P1 Button 1"}, {860, 900, "P1 Up"}, {900, 930, "P1 Button 1"}, {1000, 1008, "1 Player Start"}, {1100, 1130, "P1 Button 1"}, {1130, 1170, "P1 Left"}, {1170, 1200, "P1 Button 1"} }
return function(n)
  for _, s in ipairs(seq) do
    if n == s[1] then press(s[3], 1) end
    if n == s[2] then press(s[3], 0) end
  end
end
