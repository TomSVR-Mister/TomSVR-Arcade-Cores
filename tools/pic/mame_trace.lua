local dbg = manager.machine.debugger
dbg:command("trace pic.tr,:audiopic,noloop")
dbg:command("go")
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local done=false
emu.add_machine_frame_notifier(function()
  local t = manager.machine.time:as_double()
  if not done and t >= 1.5 then sp:write_u8(0x70001f, 0x82); done=true; print("INJ", t) end
  if t >= 2.2 then manager.machine:exit() end
end)
