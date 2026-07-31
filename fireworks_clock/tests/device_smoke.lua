-- Device-only smoke probe. Run through tools/holo.ps1 after deploying the package.
-- It loads the real package twice (hot reload), captures a PNG, writes a JSON report,
-- verifies final cleanup, and exits back to launcher.

local previous = rawget(_G, "FIREWORKS_CLOCK_SMOKE_PROBE")
if previous and previous.stop then pcall(previous.stop, "reload") end

local PROBE = {
  running = true,
  timers = {},
  report = {
    ok = false,
    package_path = "/sd/apps/fireworks_clock/main.lua",
    peak_spark_load = 0,
  },
}
_G.FIREWORKS_CLOCK_SMOKE_PROBE = PROBE

local SHOWCASE_TYPES = {
  "rapidfire",
  "spinner",
  "multibreak",
  "chrysanthemum",
  "peony",
  "willow",
  "strobe",
  "comet",
  "waterfall",
  "brocade_crown",
}

local function now_ms()
  local millis_fn = rawget(_G, "millis")
  if millis_fn then
    local ok, value = pcall(millis_fn)
    if ok and type(value) == "number" then return value end
  end
  local tmr_mod = rawget(_G, "tmr")
  if tmr_mod and tmr_mod.now then
    local ok, value = pcall(tmr_mod.now)
    if ok and type(value) == "number" then return math.floor(value / 1000) end
  end
  return 0
end

local function queue_salute(target, count, delay_frames, burst_types)
  if not target or not target.state then return end
  local state = target.state
  local base = (tonumber(state.frame) or 0) + (tonumber(delay_frames) or 0)
  for index = 0, (count or 3) - 1 do
    state.pending_launches[#state.pending_launches + 1] = {
      due = base + index * 12,
      expires = base + index * 12 + 300,
      burst_kind = burst_types and burst_types[index % #burst_types + 1] or nil,
    }
  end
end

local function load_target()
  local ok, err = pcall(dofile, PROBE.report.package_path)
  local target = rawget(_G, "FIREWORKS_CLOCK_APP")
  if not ok then return nil, tostring(err) end
  if not target or not target.running then return nil, "target did not start" end
  return target, nil
end

function PROBE.stop()
  if not PROBE.running then return end
  PROBE.running = false
  for _, timer in pairs(PROBE.timers) do
    pcall(function() timer:stop() end)
    pcall(function() timer:unregister() end)
  end
  PROBE.timers = {}
  if rawget(_G, "FIREWORKS_CLOCK_SMOKE_PROBE") == PROBE then
    _G.FIREWORKS_CLOCK_SMOKE_PROBE = nil
  end
end

local first, start_error = load_target()
PROBE.report.initial_start = first ~= nil
PROBE.report.initial_error = start_error
PROBE.report.started_ms = now_ms()
if first then queue_salute(first, 4, 0, SHOWCASE_TYPES) end

local tmr_mod = rawget(_G, "tmr")
if not (tmr_mod and tmr_mod.create) then
  PROBE.report.fatal = "tmr unavailable"
else
  PROBE.timers.reload = tmr_mod.create()
  PROBE.timers.reload:alarm(3200, tmr_mod.ALARM_SINGLE, function(timer)
    pcall(function() timer:unregister() end)
    if not PROBE.running then return end

    PROBE.report.first_frames = first and first.state and first.state.frame or -1
    local second, reload_error = load_target()
    PROBE.target = second
    PROBE.report.reload_error = reload_error
    PROBE.report.reload_ok = second ~= nil and second ~= first and first and not first.running
    PROBE.report.reload_ms = now_ms()
    -- Delay this volley so the screenshot catches active explosions, not their tail.
    if second then
      queue_salute(second, #SHOWCASE_TYPES, 25, SHOWCASE_TYPES)
      PROBE.timers.sample = tmr_mod.create()
      PROBE.timers.sample:alarm(100, tmr_mod.ALARM_AUTO, function()
        if not PROBE.running or not second.state then return end
        local load = #second.state.sparks
          + (tonumber(second.state.reserved_sparks) or 0)
        if load > PROBE.report.peak_spark_load then
          PROBE.report.peak_spark_load = load
        end
      end)
    end
  end)

  PROBE.timers.finish = tmr_mod.create()
  PROBE.timers.finish:alarm(15000, tmr_mod.ALARM_SINGLE, function(timer)
    pcall(function() timer:unregister() end)
    if not PROBE.running then return end

    local target = PROBE.target or rawget(_G, "FIREWORKS_CLOCK_APP")
    local state = target and target.state or nil
    local elapsed = math.max(1, now_ms() - (PROBE.report.reload_ms or PROBE.report.started_ms or 0))
    PROBE.report.final_running = target and target.running or false
    PROBE.report.final_frames = state and state.frame or -1
    PROBE.report.fps = state and math.floor(state.frame * 10000 / elapsed + 0.5) / 10 or 0
    PROBE.report.clock = state and state.clock_hhmm or ""
    PROBE.report.clock_valid = state and state.clock_valid or false
    PROBE.report.version = target and target.VERSION or ""
    PROBE.report.rockets = state and #state.rockets or -1
    PROBE.report.sparks = state and #state.sparks or -1
    PROBE.report.pending = state and #state.pending_launches or -1
    PROBE.report.secondary_pending = state and #state.secondary_bursts or -1
    PROBE.report.secondary_pops = state and state.secondary_pop_count or -1
    PROBE.report.reserved_sparks = state and state.reserved_sparks or -1
    PROBE.report.reservation_errors = state and state.reservation_errors or -1
    PROBE.report.rect_mode = state and state.rect_mode or -1
    if state and state.sparks then
      local min_age, max_age = nil, nil
      local visible_map = {}
      for _, spark in ipairs(state.sparks) do
        local age = tonumber(spark.age) or 0
        min_age = min_age and math.min(min_age, age) or age
        max_age = max_age and math.max(max_age, age) or age
        local name = target and target.BURST_TYPES and target.BURST_TYPES[spark.kind]
        if name then visible_map[name] = true end
      end
      PROBE.report.spark_age_min = min_age or -1
      PROBE.report.spark_age_max = max_age or -1
      local visible_types = {}
      if target and target.BURST_TYPES then
        for _, name in ipairs(target.BURST_TYPES) do
          if visible_map[name] then visible_types[#visible_types + 1] = name end
        end
      end
      PROBE.report.visible_types = visible_types
      PROBE.report.visible_type_count = #visible_types
    end
    if state and state.burst_counts then
      local counts = {}
      local type_count = 0
      for name, count in pairs(state.burst_counts) do
        counts[name] = count
        if (tonumber(count) or 0) > 0 then type_count = type_count + 1 end
      end
      PROBE.report.burst_counts = counts
      PROBE.report.burst_type_count = type_count
      PROBE.report.rapidfire_pops = counts.rapidfire or 0
      PROBE.report.spinner_pops = counts.spinner or 0
      PROBE.report.comet_pops = counts.comet or 0
      PROBE.report.waterfall_pops = counts.waterfall or 0
      PROBE.report.brocade_crown_pops = counts.brocade_crown or 0
    end

    -- Freeze the last fully committed canvas frame before taking the snapshot.
    if target and target.timers and target.timers.tick then
      pcall(function() target.timers.tick:stop() end)
    end

    local snapshot_ok, snapshot_error = false, nil
    local take = rawget(_G, "lv_snapshot_take")
    local save = rawget(_G, "lv_snapshot_save_to_png")
    local free = rawget(_G, "lv_snapshot_free")
    local scr = rawget(_G, "lv_scr_act")
    if take and save and scr then
      local ok_take, snapshot = pcall(take, scr())
      if ok_take and snapshot then
        local ok_save, saved, err = pcall(save, snapshot, "/sd/fireworks-clock-smoke.png")
        snapshot_ok = ok_save and saved == true
        if not snapshot_ok then
          snapshot_error = ok_save and tostring(err or saved) or tostring(saved)
        end
        if free then pcall(free, snapshot) end
      else
        snapshot_error = tostring(snapshot)
      end
    else
      snapshot_error = "snapshot API unavailable"
    end
    PROBE.report.snapshot_ok = snapshot_ok
    PROBE.report.snapshot_error = snapshot_error

    if target and target.stop then pcall(target.stop, "device-smoke") end
    PROBE.report.cleanup_global = rawget(_G, "FIREWORKS_CLOCK_APP") == nil
    PROBE.report.cleanup_reserved = state and state.reserved_sparks or -1
    PROBE.report.cleanup_secondary = state and #state.secondary_bursts or -1
    PROBE.report.ok = PROBE.report.initial_start
      and PROBE.report.reload_ok
      and PROBE.report.final_running
      and PROBE.report.clock_valid
      and PROBE.report.snapshot_ok
      and PROBE.report.cleanup_global
      and PROBE.report.cleanup_reserved == 0
      and PROBE.report.cleanup_secondary == 0
      and PROBE.report.reservation_errors == 0
      and PROBE.report.version == "0.12.0"
      and (PROBE.report.burst_type_count or 0) >= #SHOWCASE_TYPES
      and (PROBE.report.rapidfire_pops or 0) >= 5
      and (PROBE.report.spinner_pops or 0) >= 1
      and (PROBE.report.comet_pops or 0) >= 1
      and (PROBE.report.waterfall_pops or 0) >= 1
      and (PROBE.report.brocade_crown_pops or 0) >= 1
      and (PROBE.report.secondary_pops or 0) >= 4
      and (PROBE.report.peak_spark_load or 0) <= 150
      and PROBE.report.fps >= 20

    local codec = rawget(_G, "sjson") or rawget(_G, "json")
    local file_mod = rawget(_G, "file")
    if codec and codec.encode and file_mod and file_mod.putcontents then
      local ok_encode, payload = pcall(codec.encode, PROBE.report)
      if ok_encode then pcall(file_mod.putcontents, "/sd/fireworks-clock-smoke.json", payload) end
    end

    PROBE.stop("done")
    local app_mod = rawget(_G, "app")
    if app_mod and app_mod.exit then pcall(app_mod.exit) end
  end)
end
