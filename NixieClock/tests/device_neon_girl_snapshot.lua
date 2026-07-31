local APP_PATH = "/sd/apps/NixieClock/main.lua"
local CASES = {
  { hour = 9, min = 54, path = "/sd/apps/NixieClock/captures/face-03-v105-0954.png" },
  { hour = 10, min = 7, path = "/sd/apps/NixieClock/captures/face-03-v105-1007.png" },
}
local STATUS_PATH = "/sd/apps/NixieClock/captures/face-03-v105.status"

assert(time and type(time.getlocal) == "function", "time.getlocal unavailable")
assert(tmr and type(tmr.create) == "function", "timer unavailable")

local original_getlocal = time.getlocal
local fake_time = {
  year = 2026,
  mon = 7,
  day = 31,
  hour = CASES[1].hour,
  min = CASES[1].min,
  sec = 0,
  wday = 6,
}
local function restore_time()
  time.getlocal = original_getlocal
end

time.getlocal = function()
  return fake_time
end

local loaded, load_err = pcall(dofile, APP_PATH)
if not loaded then
  restore_time()
  error(load_err)
end

local target = rawget(_G, "HOLO_TIME_APP")
if not (target and target.running and target.canvas) then
  restore_time()
  error("NixieClock did not start")
end

target.state.face = 3
target.state.last_render_face = 0
target.state.hud_until_ms = 0

local case_index = 1
local probe_timer = tmr.create()
local armed, alarm_err = pcall(function()
  return probe_timer:alarm(900, tmr.ALARM_AUTO, function()
    local snapshot
    local ok, err = pcall(function()
      snapshot = assert(lv_snapshot_take(target.canvas), "snapshot take failed")
      local saved, save_err = lv_snapshot_save_to_png(snapshot, CASES[case_index].path)
      assert(saved, tostring(save_err or "snapshot save failed"))
    end)
    if snapshot and lv_snapshot_free then pcall(lv_snapshot_free, snapshot) end
    if not ok then
      restore_time()
      if file and file.putcontents then pcall(file.putcontents, STATUS_PATH, "error: " .. tostring(err)) end
      pcall(function() probe_timer:stop() end)
      pcall(function() probe_timer:unregister() end)
      return
    end
    case_index = case_index + 1
    if CASES[case_index] then
      fake_time.hour = CASES[case_index].hour
      fake_time.min = CASES[case_index].min
      target.state.last_render_face = 0
    else
      restore_time()
      if file and file.putcontents then pcall(file.putcontents, STATUS_PATH, "ok") end
      pcall(function() probe_timer:stop() end)
      pcall(function() probe_timer:unregister() end)
      if print then print("[NixieClock probe] ok") end
    end
  end)
end)

if not armed or not alarm_err then
  restore_time()
  error(tostring(alarm_err or "failed to arm snapshot timer"))
end
