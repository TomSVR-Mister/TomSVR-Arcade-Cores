local hook = dofile(os.getenv("HOOK"))
local frames = {}
for f in string.gmatch(os.getenv("SNAPF"), "%d+") do frames[tonumber(f)] = true end
local last = 0; for k,_ in pairs(frames) do if k>last then last=k end end
local n = 0
emu.register_frame_done(function()
  n = n + 1; hook(n)
  if frames[n] then manager.machine.video:snapshot() end
  if n >= last then manager.machine:exit() end
end)
