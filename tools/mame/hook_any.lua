local function press(field, v)
  for _, p in pairs(manager.machine.ioport.ports) do
    for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
  end
end
return function(n)
  if n == 901 then press("Coin 1", 1) end
  if n == 907 then press("Coin 1", 0) end
  if n == 1001 then press("1 Player Start", 1) end
  if n == 1007 then press("1 Player Start", 0) end
end
