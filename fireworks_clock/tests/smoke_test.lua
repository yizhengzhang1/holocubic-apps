local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assert_true(value, message)
  if not value then error(message or "expected true") end
end

local timers = {}
local alarm_should_fail = false

tmr = {
  ALARM_SINGLE = 0,
  ALARM_AUTO = 1,
}

function tmr.now()
  return 123456
end

function tmr.create()
  local timer = {
    stopped = false,
    unregistered = false,
  }
  function timer:alarm(interval, mode, callback)
    self.interval = interval
    self.mode = mode
    self.callback = callback
    return not alarm_should_fail
  end
  function timer:stop()
    self.stopped = true
    return true
  end
  function timer:unregister()
    self.unregistered = true
  end
  timers[#timers + 1] = timer
  return timer
end

local ntp_enabled = false
local ntp_init_count = 0
local now = {
  year = 2026,
  mon = 7,
  day = 30,
  hour = 10,
  min = 58,
  sec = 50,
  wday = 5,
}

time = {}
function time.settimezone(value)
  assert_eq(value, "CST-8", "timezone")
end
function time.ntpenabled()
  return ntp_enabled
end
function time.initntp(server)
  assert_eq(server, "ntp.aliyun.com", "NTP server")
  ntp_enabled = true
  ntp_init_count = ntp_init_count + 1
end
function time.getlocal()
  local copy = {}
  for key, value in pairs(now) do copy[key] = value end
  return copy
end

file = {}
function file.getcontents(path)
  assert_eq(path, "/sd/apps/settings.json", "settings path")
  return '{"timezone":"CST-8"}'
end

sjson = {}
function sjson.decode()
  return { timezone = "CST-8" }
end

local clean_count = 0
local freed_fonts = {}
local line_draw_count = 0
local line_width_counts = {}
local line_opacity_counts = {}
local line_records = {}
local rect_records = {}
function lv_scr_act() return 1 end
function lv_obj_clean()
  clean_count = clean_count + 1
end
function lv_obj_set_pos() end
function lv_obj_invalidate() end
function lv_canvas_create() return 2 end
function lv_canvas_frame_begin() return true end
function lv_canvas_frame_end() return true end
function lv_canvas_fill_bg() end
function lv_canvas_draw_line(canvas, x1, y1, x2, y2, color, opacity, width)
  line_draw_count = line_draw_count + 1
  line_width_counts[width] = (line_width_counts[width] or 0) + 1
  line_opacity_counts[opacity] = (line_opacity_counts[opacity] or 0) + 1
  line_records[#line_records + 1] = {
    x1 = x1, y1 = y1, x2 = x2, y2 = y2,
    color = color, opacity = opacity, width = width,
  }
end
function lv_canvas_draw_rect(canvas, x, y, w, h, descriptor_or_color, opacity)
  local record = {
    x = x, y = y, w = w, h = h,
  }
  if type(descriptor_or_color) == "table" then
    record.color = descriptor_or_color.bg_color
    record.opacity = descriptor_or_color.bg_opa
    record.radius = descriptor_or_color.radius
  else
    record.color = descriptor_or_color
    record.opacity = opacity
  end
  rect_records[#rect_records + 1] = record
end
function lv_canvas_draw_text() end
function lv_font_load() return 42 end
function lv_font_free(handle)
  freed_fonts[handle] = true
end

LV_IMG_CF_TRUE_COLOR = 1
LV_TEXT_ALIGN_CENTER = 1
LV_FONT_MONTSERRAT_14 = 14

local key_handlers = {}
key = {
  LEFT = 1,
  RIGHT = 2,
  UP = 3,
  DOWN = 4,
  SHORT = 2,
}
function key.on(code, callback)
  key_handlers[code] = callback
end
function key.off(code)
  key_handlers[code] = nil
end

local imu_handler = nil
app = {}
function app.on(name, callback)
  assert_eq(name, "imu", "event name")
  imu_handler = callback
end
function app.exiting() return false end

local led = { r = 0, g = 0, b = 0 }
sys = {}
function sys.setled(r, g, b)
  led.r, led.g, led.b = r or 0, g or 0, b or 0
end

function millis() return 424242 end

dofile("fireworks_clock/package/main.lua")

local target = rawget(_G, "FIREWORKS_CLOCK_APP")
assert_true(target and target.running, "app should start")
assert_eq(target.VERSION, "0.12.0", "app version")
assert_eq(ntp_init_count, 1, "NTP must initialize once")
assert_eq(#timers, 1, "one render timer")
assert_true(timers[1].callback ~= nil, "render timer callback")
assert_eq(timers[1].interval, 33, "render interval")
assert_true(imu_handler ~= nil, "IMU handler bound")
for code = 1, 4 do assert_true(key_handlers[code] ~= nil, "direction key bound") end

local function tick(count)
  for _ = 1, count do
    timers[1].callback()
    assert_true(target.running, "app remains running during tick")
  end
end

tick(8)
assert_eq(target.state.clock_hhmm, "10:58", "clock text")
assert_eq(target.state.last_hourly_key, nil, "no stale salute on normal startup")

-- A delayed tick inside the first minute must still recognize the crossed hour.
now.hour, now.min, now.sec = 11, 0, 7
target.state.last_time_query_frame = target.state.frame - 8
target.state.next_auto_launch = target.state.frame + 10000
tick(1)
assert_eq(target.state.last_hourly_key, "2026-07-30-11", "hourly salute key")
assert_true(#target.state.pending_launches >= 4, "hourly salvo queued")
local hourly_comet_queued = false
for _, item in ipairs(target.state.pending_launches) do
  if item.burst_kind == "comet" then hourly_comet_queued = true end
end
assert_true(hourly_comet_queued, "hourly showcase includes the comet")

-- A clock rollback must not create a second salute.
target.state.pending_launches = {}
target.state.rockets = {}
now.hour, now.min, now.sec = 10, 0, 0
target.state.last_time_query_frame = target.state.frame - 8
tick(1)
assert_eq(target.state.last_hourly_key, "2026-07-30-11", "rollback does not salute")
assert_eq(#target.state.pending_launches, 0, "rollback queue remains empty")

-- Direction keys enqueue a shot and the next frame launches it.
key_handlers[key.LEFT](key.SHORT)
assert_eq(#target.state.pending_launches, 1, "manual shot queued")
tick(1)
assert_eq(#target.state.pending_launches, 0, "manual shot consumed")
assert_eq(#target.state.rockets, 1, "manual rocket launched")
assert_true(target.state.reserved_sparks > 0, "manual rocket reserves its complete burst")

-- Every showcase type can be forced through the real queue, fully emitted, recycled,
-- and reused by the next type without inheriting stale object-pool fields.
target.state.rockets = {}
target.state.reserved_sparks = 0
local burst_names = {
  "peony", "chrysanthemum", "willow", "strobe",
  "spinner", "rapidfire", "multibreak", "comet",
  "waterfall", "brocade_crown",
}
local burst_budgets = { 34, 38, 20, 26, 24, 16, 52, 10, 30, 32 }
assert_eq(#target.BURST_TYPES, #burst_names, "burst type count")
for index, name in ipairs(burst_names) do
  assert_eq(target.BURST_TYPES[index], name, "burst type name")
  assert_eq(target.BURST_TYPE_IDS[name], index, "burst type id")
end
assert_eq(target.BURST_TYPE_IDS.palm, nil, "palm removed")
assert_eq(target.BURST_TYPE_IDS.spiral, nil, "spiral removed")
assert_eq(target.BURST_TYPE_IDS.crown, nil, "crown removed")
assert_eq(target.BURST_TYPE_IDS.waterfall, 9,
  "new clustered golden waterfall is registered")
assert_eq(target.BURST_TYPE_IDS.brocade_crown, 10,
  "brocade crown is distinct from the removed crown")
local simple_type_ids = { 1, 2, 3, 4, 5, 8, 9, 10 }
for _, index in ipairs(simple_type_ids) do
  local name = burst_names[index]
  target.state.pending_launches = {
    {
      due = target.state.frame,
      expires = target.state.frame + 60,
      burst_kind = name,
    },
  }
  tick(1)
  assert_eq(#target.state.rockets, 1, name .. " rocket launched")
  assert_eq(target.state.rockets[1].kind, index, name .. " rocket kind")
  assert_eq(target.state.reserved_sparks, burst_budgets[index], name .. " budget reserved")
  if name == "peony" then
    line_draw_count = 0
    line_width_counts = {}
    line_opacity_counts = {}
    line_records = {}
    rect_records = {}
    tick(1)
    local rocket = target.state.rockets[1]
    assert_true(rocket ~= nil, "standard rocket remains in flight")
    assert_true(line_draw_count >= 8,
      "standard rocket draws seven trail segments plus its bright head")
    assert_true((line_width_counts[2] or 0) >= 8,
      "standard rocket uses a two-pixel width for its half-length trail")
    assert_eq(line_width_counts[1], nil,
      "standard rocket does not leave one-pixel trail segments")
    for step = 1, 7 do
      assert_true((line_opacity_counts[235 - step * 24] or 0) >= 1,
        "standard rocket trail fades across all seven segments")
    end
    assert_true((line_opacity_counts[255] or 0) >= 1,
      "standard rocket keeps an opaque bright head")
  elseif name == "spinner" then
    local rocket = target.state.rockets[1]
    local phase_before = rocket.spin_phase
    local x_before = rocket.x
    local launch_y = rocket.y
    line_draw_count = 0
    line_width_counts = {}
    line_opacity_counts = {}
    line_records = {}
    tick(1)
    rocket = target.state.rockets[1]
    assert_true(rocket ~= nil, "spinner remains in flight")
    assert_eq(line_draw_count, 16,
      "spinner draws fourteen trail segments plus a two-line bright head")
    assert_eq(line_width_counts[2], 16,
      "spinner trail and enlarged sparse head stay at two pixels")
    assert_eq(line_width_counts[1], nil,
      "spinner does not leave one-pixel trail segments")
    assert_eq(line_width_counts[3], nil,
      "spinner head does not become a solid three-pixel block")
    assert_eq(line_opacity_counts[255], 2,
      "spinner keeps both head strokes fully opaque")
    local head_x = math.floor(rocket.x + 0.5)
    local head_y = math.floor(rocket.y)
    local center_x = math.floor(rocket.spin_center_x + 0.5)
    local horizontal = line_records[15]
    local vertical = line_records[16]
    local expected_glow_rects = {
      { size = 9, offset = 4, opacity = 56 },
      { size = 5, offset = 2, opacity = 144 },
      { size = 3, offset = 1, opacity = 240 },
    }
    for _, expected in ipairs(expected_glow_rects) do
      local found = false
      for _, record in ipairs(rect_records) do
        if record.x == head_x - expected.offset
            and record.y == head_y - expected.offset
            and record.w == expected.size
            and record.h == expected.size
            and record.opacity == expected.opacity then
          found = true
          break
        end
      end
      assert_true(found,
        "spinner keeps its centered " .. expected.size .. "x"
          .. expected.size .. " glow layer")
    end
    for step = 1, 14 do
      local segment = line_records[step]
      assert_true(math.abs(segment.x1 - center_x) <= 1,
        "spinner visible trail starts within one pixel of its center line")
      assert_true(math.abs(segment.x2 - center_x) <= 1,
        "spinner visible trail ends within one pixel of its center line")
    end
    assert_eq(horizontal.x1, head_x - 2, "spinner head horizontal left edge")
    assert_eq(horizontal.y1, head_y, "spinner head horizontal center")
    assert_eq(horizontal.x2, head_x + 2, "spinner head horizontal right edge")
    assert_eq(horizontal.y2, head_y, "spinner head horizontal alignment")
    assert_eq(vertical.x1, head_x, "spinner head vertical center")
    assert_eq(vertical.y1, head_y - 2, "spinner head vertical top edge")
    assert_eq(vertical.x2, head_x, "spinner head vertical alignment")
    assert_eq(vertical.y2, head_y + 2, "spinner head vertical bottom edge")
    for step = 1, 14 do
      assert_true((line_opacity_counts[235 - step * 12] or 0) >= 1,
        "spinner trail fades across all fourteen segments")
    end
    assert_true(rocket.spin_phase ~= phase_before, "spinner phase advances")
    assert_true(rocket.x ~= x_before, "spinner follows a rotating ascent path")
    assert_true(rocket.spin_amplitude >= 0.5 and rocket.spin_amplitude <= 1,
      "spinner ascent stays inside the half-to-one-pixel horizontal radius")
    assert_eq(rocket.vx, 0, "spinner center line does not drift")
    assert_true(rocket.vy < -3.3, "spinner uses a long, slow ascent")
    assert_true(math.abs(rocket.x - rocket.spin_center_x) <= rocket.spin_amplitude + 0.001,
      "spinner stays inside its path amplitude")
    tick(44)
    rocket = target.state.rockets[1]
    assert_true(rocket ~= nil, "spinner keeps climbing for a visibly long interval")
    assert_true(launch_y - rocket.y > 115,
      "spinner traces a long vertical ascent before exploding")
  elseif name == "comet" then
    line_draw_count = 0
    line_width_counts = {}
    line_opacity_counts = {}
    line_records = {}
    rect_records = {}
    tick(1)
    local rocket = target.state.rockets[1]
    assert_true(rocket ~= nil, "comet remains in flight")
    assert_eq(line_draw_count, 40,
      "comet ascent draws 26 main trail segments, 12 specks, and two head strokes")
    assert_eq(line_width_counts[3], 6,
      "comet ascent uses four thick inner segments plus two thick head strokes")
    assert_eq(line_width_counts[2], 10,
      "comet ascent keeps ten medium trail segments")
    assert_eq(line_width_counts[1], 24,
      "comet ascent uses twelve fine tail segments and twelve fine specks")
    assert_eq(line_opacity_counts[255], 2,
      "only the comet head cross is fully opaque")

    local head_x = math.floor(rocket.x)
    local head_y = math.floor(rocket.y)
    local expected_rects = {
      { size = 11, offset = 5, opacity = 72 },
      { size = 7, offset = 3, opacity = 168 },
      { size = 5, offset = 2, opacity = 255 },
    }
    for _, expected in ipairs(expected_rects) do
      local found = false
      for _, record in ipairs(rect_records) do
        if record.x == head_x - expected.offset
          and record.y == head_y - expected.offset
          and record.w == expected.size
          and record.h == expected.size
          and record.opacity == expected.opacity then
          found = true
          break
        end
      end
      assert_true(found,
        "comet ascent keeps its centered " .. expected.size .. "x"
          .. expected.size .. " glow layer")
    end

    local horizontal = line_records[#line_records - 1]
    local vertical = line_records[#line_records]
    assert_eq(horizontal.x1, head_x - 3, "comet head horizontal left edge")
    assert_eq(horizontal.y1, head_y, "comet head horizontal center")
    assert_eq(horizontal.x2, head_x + 3, "comet head horizontal right edge")
    assert_eq(horizontal.y2, head_y, "comet head horizontal alignment")
    assert_eq(vertical.x1, head_x, "comet head vertical center")
    assert_eq(vertical.y1, head_y - 3, "comet head vertical top edge")
    assert_eq(vertical.x2, head_x, "comet head vertical alignment")
    assert_eq(vertical.y2, head_y + 3, "comet head vertical bottom edge")
  end
  -- Stage the forced burst away from screen edges so its first rendered trail
  -- frame retains every particle for exact draw-call assertions.
  target.state.rockets[1].x = 160
  target.state.rockets[1].y = name == "comet" and 92 or 100
  target.state.rockets[1].vy = -0.69
  tick(1)
  assert_eq(#target.state.rockets, 0, name .. " rocket exploded")
  assert_eq(target.state.reserved_sparks, 0, name .. " reservation released")
  assert_eq(#target.state.sparks, burst_budgets[index], name .. " complete particle count")
  assert_eq(target.state.burst_counts[name], 1, name .. " burst counted")
  for _, spark in ipairs(target.state.sparks) do
    spark.twinkle_period = 0
    if name == "peony" then
      assert_true(spark.trail >= 4.5, "peony has a clearly visible burst trail")
    elseif name == "strobe" then
      assert_eq(spark.trail, 3.4,
        "strobe keeps a slightly longer but still compact trail")
    elseif name == "waterfall" then
      assert_eq(spark.trail, 15.0,
        "waterfall strands keep long golden trails")
      assert_eq(spark.gravity, 0.060,
        "waterfall strands pull decisively downward")
      assert_true(spark.life >= 100 and spark.life <= 124,
        "waterfall strands linger for a long cascade")
      assert_true(math.abs(spark.vx) <= 0.40,
        "waterfall strands stay inside narrow clusters")
      assert_eq(spark.core, 0xFFFFFF,
        "waterfall strands use bright white-gold heads")
      assert_eq(spark.body, 0xFFC24D,
        "waterfall strands use golden bodies")
    elseif name == "brocade_crown" then
      assert_eq(spark.trail, 11.0,
        "brocade crown keeps long fine radial trails")
      assert_eq(spark.gravity, 0.034,
        "brocade crown arcs bend gradually downward")
      assert_true(spark.life >= 82 and spark.life <= 96,
        "brocade crown keeps a long single-shell bloom")
      assert_eq(spark.draw_mode, 2,
        "brocade crown uses separate white heads and golden trails")
      assert_eq(spark.core, 0xFFFFFF,
        "brocade crown uses white-hot leading points")
      assert_eq(spark.body, 0xFFC24D,
        "brocade crown fades into gold")
    elseif name == "comet" then
      assert_true(math.abs(spark.vx) <= 0.30,
        "comet remnant has low horizontal velocity")
      assert_true(math.abs(spark.vy) <= 0.27,
        "comet remnant has low vertical velocity")
      assert_true(spark.life >= 22 and spark.life <= 28,
        "comet terminal glow lingers slightly longer")
      assert_eq(spark.trail, 3.4,
        "comet terminal flash uses a short compact trail")
      assert_eq(spark.width, 1,
        "comet terminal flash remains a fine point")
      assert_eq(spark.draw_mode, 1,
        "comet terminal flash uses the strobe head")
    end
  end

  if name == "waterfall" then
    local min_x, max_x, min_y, max_y
    for _, spark in ipairs(target.state.sparks) do
      min_x = min_x and math.min(min_x, spark.x) or spark.x
      max_x = max_x and math.max(max_x, spark.x) or spark.x
      min_y = min_y and math.min(min_y, spark.y) or spark.y
      max_y = max_y and math.max(max_y, spark.y) or spark.y
    end
    assert_true(max_x - min_x >= 75,
      "waterfall opens as five separated horizontal clusters")
    assert_true(max_y - min_y >= 20,
      "waterfall clusters begin at staggered heights")
  elseif name == "brocade_crown" then
    local min_vx, max_vx, min_vy, max_vy
    for _, spark in ipairs(target.state.sparks) do
      min_vx = min_vx and math.min(min_vx, spark.vx) or spark.vx
      max_vx = max_vx and math.max(max_vx, spark.vx) or spark.vx
      min_vy = min_vy and math.min(min_vy, spark.vy) or spark.vy
      max_vy = max_vy and math.max(max_vy, spark.vy) or spark.vy
    end
    assert_true(max_vx - min_vx >= 4.0,
      "brocade crown fills the horizontal diameter")
    assert_true(max_vy - min_vy >= 4.0,
      "brocade crown fills the vertical diameter")
  end

  line_draw_count = 0
  line_width_counts = {}
  line_opacity_counts = {}
  line_records = {}
  rect_records = {}
  tick(1)
  local lines_per_spark = (name == "strobe" or name == "comet") and 6 or 4
  assert_eq(line_draw_count, burst_budgets[index] * lines_per_spark,
    name .. " draws a tapered gradient trail on every spark")
  if name == "comet" then
    assert_eq(line_width_counts[1], burst_budgets[index] * 6,
      "comet draws four fine trail segments plus a two-line fine cross")
    assert_eq(line_width_counts[2], nil,
      "comet terminal flash does not regrow a thick tail")
    assert_eq(line_width_counts[3], nil,
      "comet terminal flash does not regrow a large head")
  else
    assert_eq(line_width_counts[2], burst_budgets[index] * 2,
      name .. " keeps the two segments nearest each bright head thick")
    local expected_thin_lines = burst_budgets[index]
      * (name == "strobe" and 4 or 2)
    assert_eq(line_width_counts[1], expected_thin_lines,
      name .. " tapers the outer trail to one pixel")
    assert_eq(line_width_counts[3], nil,
      name .. " does not inherit the comet head width")
  end
  local expected_opacities = { 255, 199, 143, 87 }
  for _, expected_opa in ipairs(expected_opacities) do
    assert_true((line_opacity_counts[expected_opa] or 0) >= burst_budgets[index],
      name .. " fades opacity along every spark trail")
  end
  if name == "brocade_crown" then
    for _, record in ipairs(line_records) do
      assert_eq(record.color, 0xFFC24D,
        "brocade crown trail remains gold behind its white head")
    end
    local head_rect_count = 0
    for _, record in ipairs(rect_records) do
      if record.w == 3 and record.h == 3
          and record.color == 0xFFFFFF and record.opacity == 255 then
        head_rect_count = head_rect_count + 1
      end
    end
    assert_eq(head_rect_count, burst_budgets[index],
      "every brocade crown strand keeps one compact white-hot head")
  end
  if name == "comet" then
    tick(11)
    assert_eq(#target.state.sparks, burst_budgets[index],
      "all ten compact comet remnants remain after twelve frames")
    assert_eq(#target.state.rockets, 0,
      "comet does not split into more rockets")
    assert_eq(#target.state.secondary_bursts, 0,
      "comet does not schedule a secondary split")
    assert_eq(target.state.burst_counts.comet, 1,
      "comet records only its single terminal burst")
    local min_x, max_x, min_y, max_y
    for _, spark in ipairs(target.state.sparks) do
      min_x = min_x and math.min(min_x, spark.x) or spark.x
      max_x = max_x and math.max(max_x, spark.x) or spark.x
      min_y = min_y and math.min(min_y, spark.y) or spark.y
      max_y = max_y and math.max(max_y, spark.y) or spark.y
    end
    assert_true(max_x - min_x <= 7,
      "comet terminal glow remains horizontally compact")
    assert_true(max_y - min_y <= 7,
      "comet terminal glow remains vertically compact")
    for _, spark in ipairs(target.state.sparks) do
      spark.age = spark.life - 2
    end
    line_draw_count = 0
    line_width_counts = {}
    line_opacity_counts = {}
    line_records = {}
    tick(1)
    assert_eq(#target.state.sparks, burst_budgets[index],
      "all comet remnants reach a final low-opacity frame")
    assert_eq(line_draw_count, burst_budgets[index] * 6,
      "fading comet remnants retain their compact trails and heads")
    local min_final_opacity, max_final_opacity
    for opacity in pairs(line_opacity_counts) do
      min_final_opacity = min_final_opacity
        and math.min(min_final_opacity, opacity) or opacity
      max_final_opacity = max_final_opacity
        and math.max(max_final_opacity, opacity) or opacity
    end
    assert_true(min_final_opacity and min_final_opacity > 0,
      "comet final frame remains faintly visible")
    assert_true(max_final_opacity and max_final_opacity < 24,
      "comet fades below the old opacity floor before disappearing")
    tick(1)
    assert_eq(#target.state.sparks, 0,
      "comet terminal glow clears after its final fade frame")
  end
  if name == "willow" then
    for _, spark in ipairs(target.state.sparks) do
      spark.age = math.floor(spark.life * spark.fade_start) + 1
    end
    line_draw_count = 0
    line_width_counts = {}
    line_opacity_counts = {}
    tick(1)
    assert_eq(line_draw_count, burst_budgets[index] * 4,
      "fading willow sparks keep all four gradient segments")
    assert_eq(line_width_counts[2], burst_budgets[index] * 2,
      "fading willow sparks keep a thick inner trail")
    assert_eq(line_width_counts[1], burst_budgets[index] * 2,
      "fading willow sparks keep a fine outer trail")
    local fading_opacity_levels = 0
    for _ in pairs(line_opacity_counts) do
      fading_opacity_levels = fading_opacity_levels + 1
    end
    assert_true(fading_opacity_levels >= 4,
      "fading willow sparks retain a visible opacity gradient")
  end
  for _, spark in ipairs(target.state.sparks) do
    assert_eq(spark.kind, index, name .. " spark kind")
    assert_true(type(spark.drag) == "number" and type(spark.gravity) == "number",
      name .. " physics fields reset")
    assert_true(type(spark.trail) == "number" and type(spark.draw_mode) == "number",
      name .. " draw fields reset")
    spark.age = spark.life - 1
  end
  tick(1)
  assert_eq(#target.state.sparks, 0, name .. " sparks recycled")
end

-- A rapidfire request expands exactly once into five lightweight, staggered shots.
local rapidfire_before = target.state.burst_counts.rapidfire or 0
target.state.pending_launches = {
  {
    due = target.state.frame,
    expires = target.state.frame + 240,
    burst_kind = "rapidfire",
  },
}
tick(1)
assert_eq(#target.state.rockets, 1, "rapidfire lead rocket launched")
assert_eq(target.state.rockets[1].kind, 6, "rapidfire rocket kind")
assert_eq(target.state.rockets[1].rapidfire_index, 1, "rapidfire lead index")
assert_eq(#target.state.pending_launches, 4, "four rapidfire follow-ups queued")
for _, item in ipairs(target.state.pending_launches) do
  assert_true(item.rapidfire_member, "rapidfire follow-up marked as a member")
  assert_true(item.rapidfire_index >= 2 and item.rapidfire_index <= 5,
    "rapidfire follow-up index")
end
local rapidfire_done = false
for _ = 1, 120 do
  for _, rocket in ipairs(target.state.rockets) do
    if rocket.kind == 6 then rocket.vy = -0.69 end
  end
  tick(1)
  assert_true(#target.state.sparks + target.state.reserved_sparks <= 150,
    "rapidfire stays inside spark budget")
  assert_true(#target.state.pending_launches <= 4,
    "rapidfire does not recursively expand")
  if #target.state.pending_launches == 0 and #target.state.rockets == 0 then
    rapidfire_done = true
    break
  end
end
assert_true(rapidfire_done, "rapidfire sequence completes")
assert_eq(target.state.burst_counts.rapidfire, rapidfire_before + 5,
  "rapidfire emits exactly five shots")
assert_eq(target.state.reserved_sparks, 0, "rapidfire reservations released")
assert_true(#target.state.sparks > 0 and #target.state.sparks <= 80,
  "rapidfire emits five lightweight bursts")
for _, spark in ipairs(target.state.sparks) do spark.twinkle_period = 0 end
line_draw_count = 0
line_width_counts = {}
line_opacity_counts = {}
tick(1)
local rapidfire_spark_count = #target.state.sparks
assert_eq(line_draw_count, rapidfire_spark_count * 4,
  "every rapidfire spark draws a tapered gradient trail")
assert_eq(line_width_counts[2], rapidfire_spark_count * 2,
  "rapidfire trails keep thick inner segments")
assert_eq(line_width_counts[1], rapidfire_spark_count * 2,
  "rapidfire trails taper to fine outer segments")
for _, spark in ipairs(target.state.sparks) do
  assert_eq(spark.kind, 6, "rapidfire spark kind")
  spark.age = spark.life - 1
end
tick(1)
assert_eq(#target.state.sparks, 0, "rapidfire sparks recycled")

-- Multibreak transfers its full reservation into four delayed child bursts.
local secondary_before = target.state.secondary_pop_count
target.state.pending_launches = {
  {
    due = target.state.frame,
    expires = target.state.frame + 60,
    burst_kind = "multibreak",
  },
}
tick(1)
assert_eq(#target.state.rockets, 1, "multibreak rocket launched")
assert_eq(target.state.rockets[1].kind, 7, "multibreak rocket kind")
assert_eq(target.state.reserved_sparks, 52, "multibreak total budget reserved")
target.state.rockets[1].vy = -0.69
tick(1)
assert_eq(#target.state.rockets, 0, "multibreak primary exploded")
assert_eq(#target.state.sparks, 12, "multibreak primary particle count")
assert_eq(#target.state.secondary_bursts, 4, "four delayed child bursts queued")
assert_eq(target.state.reserved_sparks, 40, "child burst budgets remain reserved")
assert_eq(target.state.burst_counts.multibreak, 1, "multibreak counted once")
local child_pops_seen = 0
for _ = 1, 30 do
  local pops_before_tick = target.state.secondary_pop_count
  tick(1)
  if target.state.secondary_pop_count > pops_before_tick then
    child_pops_seen = child_pops_seen + 1
    assert_eq(target.state.secondary_pop_count, pops_before_tick + 1,
      "only one delayed child pop per scheduled frame")
    assert_eq(target.state.reserved_sparks, 40 - child_pops_seen * 10,
      "child reservation converts to active sparks")
  end
  assert_true(#target.state.sparks + target.state.reserved_sparks <= 150,
    "multibreak stays inside spark budget")
end
assert_eq(child_pops_seen, 4, "four staggered child pop frames")
assert_eq(#target.state.secondary_bursts, 0, "all child bursts completed")
assert_eq(target.state.reserved_sparks, 0, "all child reservations released")
assert_eq(target.state.secondary_pop_count, secondary_before + 4, "four child pops emitted")
assert_eq(target.state.reservation_errors, 0, "multibreak reservation accounting")
assert_true(#target.state.sparks > 0 and #target.state.sparks <= 52,
  "multibreak active particle count")
for _, spark in ipairs(target.state.sparks) do spark.twinkle_period = 0 end
line_draw_count = 0
line_width_counts = {}
line_opacity_counts = {}
tick(1)
local multibreak_spark_count = #target.state.sparks
assert_eq(line_draw_count, multibreak_spark_count * 4,
  "every primary and child multibreak spark draws a tapered gradient trail")
assert_eq(line_width_counts[2], multibreak_spark_count * 2,
  "multibreak trails keep thick inner segments")
assert_eq(line_width_counts[1], multibreak_spark_count * 2,
  "multibreak trails taper to fine outer segments")
for _, spark in ipairs(target.state.sparks) do
  assert_eq(spark.kind, 7, "child spark kind")
  spark.age = spark.life - 1
end
tick(1)
assert_eq(#target.state.sparks, 0, "multibreak sparks recycled")

-- Three simultaneous dense chrysanthemums reserve their full budgets and stay under the cap.
target.state.pending_launches = {}
for i = 1, 3 do
  target.state.pending_launches[i] = {
    due = target.state.frame,
    expires = target.state.frame + 60,
    burst_kind = "chrysanthemum",
  }
end
tick(1)
assert_eq(#target.state.rockets, 3, "three reserved rockets launched")
assert_eq(target.state.reserved_sparks, 114, "three chrysanthemum budgets reserved")
for _, rocket in ipairs(target.state.rockets) do rocket.vy = -0.69 end
tick(1)
assert_eq(#target.state.rockets, 0, "three chrysanthemums exploded")
assert_eq(target.state.reserved_sparks, 0, "all chrysanthemum reservations released")
assert_eq(#target.state.sparks, 114, "all chrysanthemum particles emitted")
assert_true(#target.state.sparks <= 150, "spark cap respected")
for _, spark in ipairs(target.state.sparks) do spark.age = spark.life - 1 end
tick(1)
assert_eq(#target.state.sparks, 0, "simultaneous chrysanthemum particles recycled")

-- Capacity pressure keeps a queued launch instead of dropping it.
local palette = { core = 0xFFFFFF, body = 0x00FFFF }
target.state.reserved_sparks = 0
target.state.rockets = {}
for index = 1, 5 do
  target.state.rockets[index] = {
    x = index * 52, y = 220, vx = 0, vy = -2, apex_y = 40, palette = palette,
  }
end
target.state.pending_launches = {
  {
    due = target.state.frame,
    expires = target.state.frame + 60,
    burst_kind = "peony",
  },
}
tick(1)
assert_eq(#target.state.pending_launches, 1, "blocked shot retained")
target.state.rockets = {}
tick(5)
assert_eq(#target.state.pending_launches, 0, "blocked shot retries")
assert_eq(#target.state.rockets, 1, "retried rocket launched")

-- Crossing +180/-180 is a two-degree move, not a shake.
target.state.pending_launches = {}
target.state.imu_last_roll = 179
target.state.imu_last_pitch = 0
target.state.imu_armed = true
target.state.imu_spike_count = 0
imu_handler("imu", -179, 0, 0, 0, 0, 1000)
imu_handler("imu", 179, 0, 0, 0, 0, 1060)
assert_eq(#target.state.pending_launches, 0, "wrapped angles do not trigger")

-- Two fast, real orientation spikes trigger one three-shot volley.
target.state.imu_last_roll = 0
target.state.imu_last_pitch = 0
imu_handler("imu", 24, 0, 0, 0, 0, 1200)
imu_handler("imu", -8, 0, 0, 0, 0, 1280)
assert_eq(#target.state.pending_launches, 3, "shake volley queued")
assert_eq(target.state.imu_armed, false, "shake detector disarmed")

target.state.led_on = true
target.stop("host-smoke")
assert_eq(rawget(_G, "FIREWORKS_CLOCK_APP"), nil, "global cleared")
assert_true(timers[1].stopped and timers[1].unregistered, "timer released")
assert_eq(imu_handler, nil, "IMU handler released")
for code = 1, 4 do assert_eq(key_handlers[code], nil, "direction key released") end
assert_true(freed_fonts[42], "dynamic font released")
assert_eq(led.r + led.g + led.b, 0, "LED turned off")
assert_true(clean_count >= 2, "screen cleaned on init and stop")
assert_eq(target.state.reserved_sparks, 0, "stop releases all reservations")
assert_eq(target.state.reservation_errors, 0, "no reservation faults")

-- A timer that refuses to start must fail closed and clean all resources.
alarm_should_fail = true
dofile("fireworks_clock/package/main.lua")
assert_eq(rawget(_G, "FIREWORKS_CLOCK_APP"), nil, "failed timer leaves no live app")
assert_true(timers[#timers].unregistered, "failed timer is unregistered")

print("fireworks_clock smoke test: OK")
