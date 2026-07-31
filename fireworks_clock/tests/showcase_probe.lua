-- Device-only visual QA probe for every Fireworks Clock burst type.
-- It injects one fully reserved rocket at a controlled position, captures the
-- developed shape, then clears the scene before moving to the next type.

local previous = rawget(_G, "FIREWORKS_SHOWCASE_PROBE")
if previous and previous.stop then pcall(previous.stop, "reload") end

local PROBE = {
  running = true,
  timers = {},
  report = {
    ok = false,
    package_path = "/sd/apps/fireworks_clock/main.lua",
    shots = {},
  },
}
_G.FIREWORKS_SHOWCASE_PROBE = PROBE

local TYPES = {
  "peony", "chrysanthemum", "willow", "strobe",
  "spinner", "multibreak", "rapidfire", "comet",
  "waterfall", "brocade_crown",
}
local TYPE_IDS = { 1, 2, 3, 4, 5, 7, 6, 8, 9, 10 }
local BUDGETS = { 34, 38, 20, 26, 24, 52, 16, 10, 30, 32 }
local PALETTES = {
  { core = 0xD8FFF6, body = 0x4DE8FF, index = 2 },
  { core = 0xFFE0F4, body = 0xFF5FD0, index = 3 },
  { core = 0xFFF6C8, body = 0xFFC24D, index = 1 },
  { core = 0xE8FFDC, body = 0x8CFF5A, index = 4 },
  { core = 0xE0E8FF, body = 0x6E8CFF, index = 5 },
  { core = 0xD8FFF6, body = 0x4DE8FF, index = 2 },
  { core = 0xFFF0DC, body = 0xFF7A48, index = 6 },
  { core = 0xF4FAFF, body = 0xFFC24D, index = 1 },
  { core = 0xFFFFFF, body = 0xFFC24D, index = 1 },
  { core = 0xFFFFFF, body = 0xFFC24D, index = 1 },
}
local POSITIONS = {
  { x = 160, y = 90 },
  { x = 160, y = 88 },
  { x = 160, y = 54 },
  { x = 160, y = 104 },
  { x = 160, y = 86 },
  { x = 160, y = 82 },
  { x = 160, y = 138 },
  { x = 160, y = 92 },
  { x = 160, y = 56 },
  { x = 160, y = 80 },
}

local function write_report()
  local codec = rawget(_G, "sjson") or rawget(_G, "json")
  local file_mod = rawget(_G, "file")
  if codec and codec.encode and file_mod and file_mod.putcontents then
    local ok, payload = pcall(codec.encode, PROBE.report)
    if ok then pcall(file_mod.putcontents, "/sd/fireworks-showcase.json", payload) end
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
  if PROBE.target and PROBE.target.stop then pcall(PROBE.target.stop, "showcase-probe") end
  if rawget(_G, "FIREWORKS_SHOWCASE_PROBE") == PROBE then
    _G.FIREWORKS_SHOWCASE_PROBE = nil
  end
end

local ok_load, load_error = pcall(dofile, PROBE.report.package_path)
local target = rawget(_G, "FIREWORKS_CLOCK_APP")
PROBE.target = target
PROBE.report.loaded = ok_load and target and target.running or false
PROBE.report.load_error = ok_load and nil or tostring(load_error)
PROBE.report.version = target and target.VERSION or ""

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

  local function inject(index)
    local state = target.state
    local name = TYPES[index]
    state.pending_launches = {}
    state.rockets = {}
    state.sparks = {}
    state.secondary_bursts = {}
    state.reserved_sparks = 0
    state.next_auto_launch = state.frame + 10000
    -- 视觉质检快照隐藏时钟，避免字形遮住烟花轮廓。
    state.clock_hhmm = ""
    state.clock_date = ""
    state.clock_valid = false
    state.last_time_query_frame = state.frame + 10000
    local palette = PALETTES[index]
    local position = POSITIONS[index]
    if name == "rapidfire" then
      state.pending_launches[1] = {
        due = state.frame,
        expires = state.frame + 300,
        burst_kind = "rapidfire",
      }
      return
    end
    if name == "spinner" then
      state.reserved_sparks = BUDGETS[index] * 2
      state.rockets[1] = {
        x = position.x,
        y = position.y,
        vx = 0,
        vy = -0.69,
        apex_y = position.y,
        palette = palette,
        palette_index = palette.index,
        tail_color = palette.body,
        kind = TYPE_IDS[index],
        budget = BUDGETS[index],
        reserved = BUDGETS[index],
        spin_center_x = position.x,
        spin_phase = 0,
        spin_speed = 0.39,
        spin_amplitude = 0.75,
        rapidfire_index = 0,
        prev_x = position.x,
        prev_y = position.y,
      }
      state.rockets[2] = {
        x = 211,
        y = 228,
        vx = 0,
        vy = -3.55,
        apex_y = 62,
        palette = palette,
        palette_index = palette.index,
        tail_color = palette.body,
        kind = TYPE_IDS[index],
        budget = BUDGETS[index],
        reserved = BUDGETS[index],
        spin_center_x = 210,
        spin_phase = math.pi * 0.5,
        spin_speed = -0.40,
        spin_amplitude = 1,
        rapidfire_index = 0,
        prev_x = 211,
        prev_y = 224,
      }
      return
    end
    state.reserved_sparks = BUDGETS[index]
    state.rockets[1] = {
      x = position.x,
      y = position.y,
      vx = 0,
      vy = -0.69,
      apex_y = position.y,
      palette = palette,
      palette_index = palette.index,
      tail_color = palette.body,
      kind = TYPE_IDS[index],
      budget = BUDGETS[index],
      reserved = BUDGETS[index],
      spin_center_x = position.x,
      spin_phase = 0,
      spin_speed = 0,
      spin_amplitude = 0,
      rapidfire_index = 0,
      prev_x = position.x,
      prev_y = position.y,
    }
  end

  local function capture(index)
    local take = rawget(_G, "lv_snapshot_take")
    local save = rawget(_G, "lv_snapshot_save_to_png")
    local free = rawget(_G, "lv_snapshot_free")
    local scr = rawget(_G, "lv_scr_act")
    local name = TYPES[index]
    local saved_ok = false
    if take and save and scr then
      local ok_take, snapshot = pcall(take, scr())
      if ok_take and snapshot then
        local ok_save, saved = pcall(save, snapshot, "/sd/fireworks-showcase-" .. name .. ".png")
        saved_ok = ok_save and saved == true
        if free then pcall(free, snapshot) end
      end
    end
    PROBE.report.shots[name] = saved_ok
  end

  local function finish()
    local all_ok = true
    for _, name in ipairs(TYPES) do
      if PROBE.report.shots[name] ~= true then all_ok = false end
    end
    PROBE.report.ok = all_ok
    write_report()
    PROBE.stop("done")
    local app_mod = rawget(_G, "app")
    if app_mod and app_mod.exit then pcall(app_mod.exit) end
  end

  local function run_type(index)
    inject(index)
    local capture_delay = 900
    if TYPES[index] == "spinner" then
      capture_delay = 900
    elseif TYPES[index] == "multibreak" then
      capture_delay = 1100
    elseif TYPES[index] == "rapidfire" then
      capture_delay = 1900
    elseif TYPES[index] == "comet" then
      -- This probe stages the terminal burst directly. Capture while the
      -- lingering remnants still form one compact glow instead of after fade-out.
      capture_delay = 350
    elseif TYPES[index] == "waterfall" then
      capture_delay = 2200
    elseif TYPES[index] == "brocade_crown" then
      capture_delay = 1050
    end
    schedule(capture_delay, function()
      capture(index)
      schedule(500, function()
        if index < #TYPES then
          run_type(index + 1)
        else
          finish()
        end
      end)
    end)
  end

  schedule(200, function() run_type(1) end)
end
