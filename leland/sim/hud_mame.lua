local m = manager.machine
local scr = m.screens:at(1)
local function beam()
    local remain = scr:time_until_pos(0,0)
    local elapsed = (scr.frame_period - remain) % scr.frame_period
    local y = math.floor(elapsed / scr.scan_period)
    local x = math.floor((elapsed - y * scr.scan_period) / scr.pixel_period)
    return y,x
end
local out = io.open('mame_hud_trace.log', 'w')
local fields = {}
for tag, port in pairs(m.ioport.ports) do
    for name, field in pairs(port.fields) do
        out:write(tag .. ' ' .. name .. '\n')
        fields[name] = field
    end
end
local master = m.devices[':master']
HUD_TAPS = {}
local taps = HUD_TAPS
taps[1] = master.spaces['io']:install_write_tap(0, 255, 'hudscroll', function(offset, data, mask)
    offset = offset & 255
    if offset == 0xf0 or offset == 0xf1 or offset == 0xf2 or offset == 0xf3 or
       offset == 0xcc or offset == 0xcd or offset == 0xce or offset == 0xcf or
       offset == 0x8c or offset == 0x8d or offset == 0x8e or offset == 0x8f or
       offset == 0x4c or offset == 0x4d or offset == 0x4e or offset == 0x4f or offset == 0xf8 then
        local y,x = beam()
        out:write(string.format('IO f=%d y=%d x=%d pc=%04x port=%02x data=%02x\n',
            scr:frame_number(), y, x, master.state['PC'].value, offset, data))
    end
end)
local function set(names, value)
    for _, name in ipairs(names) do
        if fields[name] then fields[name]:set_value(value); return end
    end
    out:write('MISSING INPUT ' .. table.concat(names, ',') .. '\n')
end
emu.register_frame_done(function()
    taps[1]:reinstall()
    local f = scr:frame_number()
    if f == 145 then set({'Coin 1'}, 1) end
    if f == 156 then set({'Coin 1'}, 0) end
    if f == 198 then set({'1 Player Start', 'P1 Start', 'Start 1'}, 1) end
    if f == 209 then set({'1 Player Start', 'P1 Start', 'Start 1'}, 0) end
    if f == 400 then set({'Coin 1'}, 1) end
    if f == 411 then set({'Coin 1'}, 0) end
    if f == 460 or f == 510 then set({'1 Player Start', 'P1 Start', 'Start 1'}, 1) end
    if f == 471 or f == 521 then set({'1 Player Start', 'P1 Start', 'Start 1'}, 0) end
    if f == 230 or f == 540 then set({'P1 Button 1'}, 1) end
    if f == 241 or f == 551 then set({'P1 Button 1'}, 0) end
    if f == 610 or f == 630 or f == 650 or f == 670 then set({'P1 Button 1'}, 1) end
    if f == 620 or f == 640 or f == 660 or f == 680 then set({'P1 Button 1'}, 0) end
    if f == 700 then set({'P1 Right'}, 1) end
    if f == 900 then set({'P1 Right'}, 0) end
    if f % 50 == 0 and f >= 350 then scr:snapshot(string.format('mame_%d.png', f)) end
    if f == 260 or f == 300 or f == 340 then scr:snapshot(string.format('mame_%d.png', f)) end
    if f % 60 == 0 then out:flush() end
    if f == 560 or f == 600 or f == 650 then scr:snapshot(string.format('mame_%d.png', f)) end
    if f == (m.devices[':'].items['0/:qram'] and 600 or 850) then
        for _, key in ipairs({'0/m_gfxbank','0/m_xscroll','0/m_yscroll'}) do
            local id=m.devices[':'].items[key]
            if id then out:write(string.format('STATE f=%d key=%s value=%04x\n', f,key,emu.item(id):read(0))) end
        end
        for _, item in ipairs({{'0/m_video_ram',131072,'fg'}, {'0/:qram',65536,'qram'}, {'0/:palette',m.devices[':'].items['0/:qram'] and 2048 or 1024,'palette'}}) do
            local id = m.devices[':'].items[item[1]]
            if id then
                local dump = io.open('mame_'..item[3]..'.bin','wb')
                dump:write(emu.item(id):read_block(0,item[2])); dump:close()
            end
        end
    end
    if f >= 1000 then out:close(); m:exit() end
end)
