-- Device-only capture probe for the Spinner gallery GIF.
-- Captures 16 native 320x240 PNG frames from the long, narrow ascent through
-- the spinner burst, using the production queue and reservation lifecycle.

local previous = rawget(_G, "FIREWORKS_SPINNER_GIF_CAPTURE_PROBE")
if previous and previous.stop then pcall(previous.stop, "reload") end

local OUTPUT_DIR = "/sd/fireworks-spinner-gif"
local REPORT_PATH = "/sd/fireworks-spinner-gif-report.json"
local FRAME_COUNT = 16
local FRAME_INTERVAL_MS = 180
local EXPECTED_VERSION = "0.12.0"
local SPINNER_KIND = 5

local PROBE = {
  running = true,
  timers = {},
  report = {
    ok = false,
    package_path = "/sd/apps/fireworks_clock/main.lua",
    output_dir = OUTPUT_DIR,
    report_path = REPORT_PATH,
    frame_count = FRAME_COUNT,
    frame_interval_ms = FRAME_INTERVAL_MS,
    expected_version = EXPECTED_VERSION,
    width = 320,
    height = 240,
    captures = { spinner = 0 },
  },
}
_G.FIREWORKS_SPINNER_GIF_CAPTURE_PROBE = PROBE

local function write_report()
  local codec = rawget(_G, "sjson") or rawget(_G, "json")
  local file_mod = rawget(_G, "file")
  if codec and codec.encode and file_mod and file_mod.putcontents then
    local ok, payload = pcall(codec.encode, PROBE.report)
    if ok then pcall(file_mod.putcontents, REPORT_PATH, payload) end
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
    pcall(PROBE.target.stop, "spinner-gif-capture-probe")
  end
  if rawget(_G, "FIREWORKS_SPINNER_GIF_CAPTURE_PROBE") == PROBE then
    _G.FIREWORKS_SPINNER_GIF_CAPTURE_PROBE = nil
  end
end

local function stop_and_exit(reason)
  PROBE.stop(reason)
  local app_mod = rawget(_G, "app")
  if app_mod and app_mod.exit then pcall(app_mod.exit) end
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
  stop_and_exit("startup-failed")
else
  local function schedule(delay_ms, callback)
    local timer = tmr_mod.create()
    PROBE.timers[#PROBE.timers + 1] = timer
    timer:alarm(delay_ms, tmr_mod.ALARM_SINGLE, function(current)
      pcall(function() current:unregister() end)
      if PROBE.running then
        local ok, callback_error = pcall(callback)
        if not ok then
          PROBE.report.fatal = "callback failed: " .. tostring(callback_error)
          write_report()
          stop_and_exit("callback-failed")
        end
      end
    end)
  end

  local function scene_is_reservation_clean()
    local state = target.state
    return #state.pending_launches == 0
      and #state.rockets == 0
      and #state.secondary_bursts == 0
      and (tonumber(state.reserved_sparks) or 0) == 0
  end

  local function prepare_scene()
    local state = target.state
    PROBE.report.reservation_errors_start = tonumber(state.reservation_errors) or 0
    if not scene_is_reservation_clean() then
      PROBE.report.fatal = "initial scene owns reservations"
      return false
    end

    -- Keep automatic, hourly, and IMU-triggered launches out of the capture.
    -- The long cooldown prevents calm IMU samples from re-arming the gesture.
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
    state.imu_last_roll = nil
    state.imu_last_pitch = nil

    -- Use the production queue/spawn path so the rocket owns a real spark
    -- reservation throughout ascent and releases it through normal lifecycle.
    state.pending_launches[#state.pending_launches + 1] = {
      due = state.frame,
      expires = state.frame + 300,
      burst_kind = "spinner",
    }
    PROBE.report.inject_frame = state.frame
    return true
  end

  local function stage_spinner()
    local state = target.state
    for _, rocket in ipairs(state.rockets) do
      if rocket.kind == SPINNER_KIND then
        -- A deterministic ultra-tight 1 px helix spans nearly the full display height.
        -- The apex timing leaves the final six captures for the burst.
        rocket.x = 160
        rocket.y = 224
        rocket.vx = 0
        rocket.vy = -3.65
        rocket.apex_y = 76
        rocket.prev_x = rocket.x
        rocket.prev_y = rocket.y
        rocket.spin_center_x = 160
        rocket.spin_phase = 0
        rocket.spin_speed = 0.40
        rocket.spin_amplitude = 1
        PROBE.report.staged = true
        PROBE.report.stage_frame = state.frame
        PROBE.report.stage_x = rocket.x
        PROBE.report.stage_y = rocket.y
        PROBE.report.stage_vy = rocket.vy
        PROBE.report.stage_apex_y = rocket.apex_y
        PROBE.report.spin_speed = rocket.spin_speed
        PROBE.report.spin_amplitude = rocket.spin_amplitude
        PROBE.report.rocket_budget = tonumber(rocket.budget) or 0
        PROBE.report.rocket_reserved = tonumber(rocket.reserved) or 0
        return true
      end
    end
    return false
  end

  local function capture_frame(frame)
    local take = rawget(_G, "lv_snapshot_take")
    local save = rawget(_G, "lv_snapshot_save_to_png")
    local free = rawget(_G, "lv_snapshot_free")
    local scr = rawget(_G, "lv_scr_act")
    local saved_ok = false
    local label = frame < 10 and ("0" .. frame) or tostring(frame)
    local path = OUTPUT_DIR .. "/spinner-" .. label .. ".png"

    if take and save and scr then
      local ok_take, snapshot = pcall(take, scr())
      if ok_take and snapshot then
        local ok_save, saved = pcall(save, snapshot, path)
        saved_ok = ok_save and saved == true
        if free then pcall(free, snapshot) end
      end
    end

    if saved_ok then
      PROBE.report.captures.spinner = PROBE.report.captures.spinner + 1
    end
    PROBE.report.last_capture_frame = target.state.frame
    return saved_ok
  end

  local function finish()
    local state = target.state
    local reservation_errors_end = tonumber(state.reservation_errors) or 0
    PROBE.report.reservation_errors_end = reservation_errors_end
    PROBE.report.reserved_sparks = tonumber(state.reserved_sparks) or 0
    PROBE.report.final_pending = #state.pending_launches
    PROBE.report.final_rockets = #state.rockets
    PROBE.report.final_secondary_bursts = #state.secondary_bursts
    PROBE.report.final_sparks = #state.sparks
    PROBE.report.ok = PROBE.report.version_matches == true
      and PROBE.report.staged == true
      and PROBE.report.rocket_reserved == PROBE.report.rocket_budget
      and PROBE.report.rocket_budget > 0
      and PROBE.report.captures.spinner == FRAME_COUNT
      and scene_is_reservation_clean()
      and reservation_errors_end == PROBE.report.reservation_errors_start
    write_report()
    stop_and_exit("done")
  end

  local function wait_for_clean(attempt)
    if scene_is_reservation_clean() then
      finish()
    elseif attempt >= 60 then
      PROBE.report.fatal = "reservation drain timeout"
      finish()
    else
      schedule(100, function() wait_for_clean(attempt + 1) end)
    end
  end

  local function capture_sequence(frame)
    capture_frame(frame)
    if frame < FRAME_COUNT then
      schedule(FRAME_INTERVAL_MS, function()
        capture_sequence(frame + 1)
      end)
    else
      schedule(300, function() wait_for_clean(1) end)
    end
  end

  local function wait_for_spinner(attempt)
    if stage_spinner() then
      schedule(80, function() capture_sequence(1) end)
    elseif attempt >= 25 then
      PROBE.report.fatal = "spinner rocket did not spawn"
      write_report()
      stop_and_exit("spawn-failed")
    else
      schedule(20, function() wait_for_spinner(attempt + 1) end)
    end
  end

  schedule(200, function()
    if prepare_scene() then
      wait_for_spinner(1)
    else
      write_report()
      stop_and_exit("prepare-failed")
    end
  end)
end
