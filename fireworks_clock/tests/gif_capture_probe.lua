-- Device-only frame capture probe for the animated Fireworks Clock gallery.
-- The host converts the captured 320x240 PNG frames into optimized GIF files.

local previous = rawget(_G, "FIREWORKS_GIF_CAPTURE_PROBE")
if previous and previous.stop then pcall(previous.stop, "reload") end

local OUTPUT_DIR = "/sd/fireworks-gif"
local FRAME_COUNT = 16
local FRAME_INTERVAL_MS = 180
local EXPECTED_VERSION = "0.12.0"

local PROBE = {
  running = true,
  timers = {},
  report = {
    ok = false,
    package_path = "/sd/apps/fireworks_clock/main.lua",
    output_dir = OUTPUT_DIR,
    frame_count = FRAME_COUNT,
    frame_interval_ms = FRAME_INTERVAL_MS,
    expected_version = EXPECTED_VERSION,
    captures = {},
  },
}
_G.FIREWORKS_GIF_CAPTURE_PROBE = PROBE

local TYPES = {
  "peony", "chrysanthemum", "willow", "strobe",
  "spinner", "multibreak", "rapidfire", "comet",
  "waterfall", "brocade_crown",
}
local TYPE_IDS = {
  peony = 1,
  chrysanthemum = 2,
  willow = 3,
  strobe = 4,
  spinner = 5,
  rapidfire = 6,
  multibreak = 7,
  comet = 8,
  waterfall = 9,
  brocade_crown = 10,
}
PROBE.report.type_count = #TYPES
PROBE.report.total_frame_count = FRAME_COUNT * #TYPES

local function write_report()
  local codec = rawget(_G, "sjson") or rawget(_G, "json")
  local file_mod = rawget(_G, "file")
  if codec and codec.encode and file_mod and file_mod.putcontents then
    local ok, payload = pcall(codec.encode, PROBE.report)
    if ok then pcall(file_mod.putcontents, OUTPUT_DIR .. "/report.json", payload) end
  end
end

function PROBE.stop()
  if not PROBE.running then return end
  PROBE.running = false
  for _, timer in ipairs(PROBE.timers) do
    pcall(function() timer:stop() end)
    pcall(function() timer:unregister() end)
  end
  PROBE.timers = {}
  if PROBE.target and PROBE.target.stop then
    pcall(PROBE.target.stop, "gif-capture-probe")
  end
  if rawget(_G, "FIREWORKS_GIF_CAPTURE_PROBE") == PROBE then
    _G.FIREWORKS_GIF_CAPTURE_PROBE = nil
  end
end

local ok_load, load_error = pcall(dofile, PROBE.report.package_path)
local target = rawget(_G, "FIREWORKS_CLOCK_APP")
PROBE.target = target
PROBE.report.loaded = ok_load and target and target.running or false
PROBE.report.load_error = ok_load and nil or tostring(load_error)
PROBE.report.version = target and target.VERSION or ""
PROBE.report.version_matches = PROBE.report.version == EXPECTED_VERSION

local file_mod = rawget(_G, "file")
if file_mod and file_mod.mkdir then
  pcall(file_mod.mkdir, OUTPUT_DIR)
end

local tmr_mod = rawget(_G, "tmr")
if not (PROBE.report.loaded and tmr_mod and tmr_mod.create) then
  PROBE.report.fatal = "target or timer unavailable"
  write_report()
  PROBE.stop("startup-failed")
else
  local function schedule(delay_ms, callback)
    local timer = tmr_mod.create()
    PROBE.timers[#PROBE.timers + 1] = timer
    timer:alarm(delay_ms, tmr_mod.ALARM_SINGLE, function(current)
      pcall(function() current:unregister() end)
      if PROBE.running then callback() end
    end)
  end

  local function reset_scene(name)
    local state = target.state
    state.pending_launches = {}
    state.rockets = {}
    state.sparks = {}
    state.secondary_bursts = {}
    state.reserved_sparks = 0
    state.next_auto_launch = state.frame + 10000
    state.clock_hhmm = ""
    state.clock_date = ""
    state.clock_valid = false
    state.last_time_query_frame = state.frame + 10000
    state.flash_until = 0
    state.shake_cooldown_until = state.frame + 10000
    state.imu_armed = false
    state.imu_calm_samples = 0
    state.imu_spike_count = 0
    state.pending_launches[1] = {
      due = state.frame,
      expires = state.frame + 300,
      burst_kind = name,
    }
  end

  local function stage_lead_rocket(name)
    if name == "rapidfire" then return end
    local state = target.state
    local expected_kind = TYPE_IDS[name]
    for _, rocket in ipairs(state.rockets) do
      if rocket.kind == expected_kind then
        rocket.x = 160
        rocket.y = 222
        rocket.vx = name == "spinner" and 0 or 0.12
        rocket.prev_x = rocket.x
        rocket.prev_y = rocket.y
        if name == "waterfall" then
          -- Start at the burst so the short GIF can show the long gold
          -- curtains opening and falling instead of spending half its time
          -- on the production ascent.
          rocket.y = 52
          rocket.vx = 0
          rocket.vy = -0.69
          rocket.apex_y = rocket.y
        elseif name == "brocade_crown" then
          -- Give the full circular shell time to spread, bend and fade.
          rocket.y = 80
          rocket.vx = 0
          rocket.vy = -0.69
          rocket.apex_y = rocket.y
        elseif name == "spinner" then
          rocket.vy = -3.15
          rocket.apex_y = 145
          rocket.spin_center_x = 160
          rocket.spin_phase = 0
          rocket.spin_speed = 0.40
          rocket.spin_amplitude = 1
          rocket.x = rocket.spin_center_x
        elseif name == "comet" then
          -- Preserve the single bright ascent head and its dense long tail;
          -- the terminal burst now remains a compact glow instead of fanning out.
          rocket.vx = 0.18
          rocket.vy = -4.90
          rocket.apex_y = 92
        else
          rocket.vy = -2.80
          rocket.apex_y = 164
        end
        return
      end
    end
  end

  local function capture_frame(name, frame)
    local take = rawget(_G, "lv_snapshot_take")
    local save = rawget(_G, "lv_snapshot_save_to_png")
    local free = rawget(_G, "lv_snapshot_free")
    local scr = rawget(_G, "lv_scr_act")
    local saved_ok = false
    if take and save and scr then
      local ok_take, snapshot = pcall(take, scr())
      if ok_take and snapshot then
        local label = frame < 10 and ("0" .. frame) or tostring(frame)
        local path = OUTPUT_DIR .. "/" .. name .. "-" .. label .. ".png"
        local ok_save, saved = pcall(save, snapshot, path)
        saved_ok = ok_save and saved == true
        if free then pcall(free, snapshot) end
      end
    end
    if saved_ok then
      PROBE.report.captures[name] = (PROBE.report.captures[name] or 0) + 1
    end
  end

  local function finish()
    local all_ok = PROBE.report.version_matches == true
    for _, name in ipairs(TYPES) do
      if PROBE.report.captures[name] ~= FRAME_COUNT then all_ok = false end
    end
    PROBE.report.ok = all_ok
    write_report()
    PROBE.stop("done")
    local app_mod = rawget(_G, "app")
    if app_mod and app_mod.exit then pcall(app_mod.exit) end
  end

  local run_type
  run_type = function(index)
    local name = TYPES[index]
    reset_scene(name)
    schedule(100, function()
      stage_lead_rocket(name)
      local frame = 1
      local function take_next()
        capture_frame(name, frame)
        if frame < FRAME_COUNT then
          frame = frame + 1
          schedule(FRAME_INTERVAL_MS, take_next)
        else
          schedule(300, function()
            if index < #TYPES then
              run_type(index + 1)
            else
              finish()
            end
          end)
        end
      end
      schedule(80, take_next)
    end)
  end

  schedule(200, function() run_type(1) end)
end
