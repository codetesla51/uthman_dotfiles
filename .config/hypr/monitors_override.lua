-- Monitor override written by the quickshell Monitors panel
-- (~/.config/hypr/monitors-override.conf). That file is hyprlang text:
--     monitor = <name>,<mode>,<pos>,<scale>[,<key>,<value>]...
-- and used to be `source`d after monitors.conf so that it wins. Hyprland only
-- reads .conf files while a hyprlang config is active, so it is parsed and
-- re-applied here. The panel keeps writing .conf — no quickshell change needed.

local path = os.getenv("HOME") .. "/.config/hypr/monitors-override.conf"
local f = io.open(path, "r")
if not f then return end

for line in f:lines() do
  local spec = line:match("^%s*monitor%s*=%s*(.+)$") -- a leading '#' won't match
  if spec then
    local parts = {}
    for field in spec:gmatch("[^,]+") do
      parts[#parts + 1] = field:match("^%s*(.-)%s*$")
    end

    local mon = { output = parts[1], mode = parts[2], position = parts[3] }
    if parts[4] then
      mon.scale = tonumber(parts[4]) or parts[4]
    end

    -- trailing key,value pairs (transform, vrr, mirror, bitdepth, ...)
    for i = 5, #parts - 1, 2 do
      local k, v = parts[i], parts[i + 1]
      if k == "transform" or k == "vrr" or k == "bitdepth" then
        mon[k] = tonumber(v) or v
      else
        mon[k] = v
      end
    end

    pcall(hl.monitor, mon)
  end
end
f:close()
