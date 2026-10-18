local function press(field, v)
  for _, p in pairs(manager.machine.ioport.ports) do
    for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
  end
end
return function(n)
  if n == 201 then press("Coin 1", 1) end
  if n == 207 then press("Coin 1", 0) end
  if n == 301 then press("1 Player Start", 1) end
  if n == 307 then press("1 Player Start", 0) end
  if n == 401 then press("P1 Button 1", 1) end
  if n == 407 then press("P1 Button 1", 0) end
  if n == 501 then press("P1 Right", 1) end
  if n == 561 then press("P1 Right", 0) end
  if n == 601 then press("P1 Button 1", 1) end
  if n == 661 then press("P1 Up", 1) end
  if n == 721 then press("P1 Up", 0) end
  if n == 761 then press("P1 Button 1", 0) end
end
