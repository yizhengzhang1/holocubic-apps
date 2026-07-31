local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assert_true(value, message)
  if not value then error(message or "expected true") end
end

local now = {
  year = 2026,
  mon = 7,
  day = 31,
  hour = 9,
  min = 54,
  sec = 0,
  wday = 6,
}

time = {}
function time.settimezone() end
function time.initntp() end
function time.getlocal()
  local copy = {}
  for key, value in pairs(now) do copy[key] = value end
  return copy
end

file = {}
function file.getcontents(path)
  if path == "/sd/apps/settings.json" then return '{"kind":"settings"}' end
  if path == "/sd/apps/NixieClock/config.json" then return '{"kind":"config"}' end
  return nil
end

sjson = {}
function sjson.decode(raw)
  if raw == '{"kind":"settings"}' then return { timezone = "CST-8", city = "SHENZHEN" } end
  if raw == '{"kind":"config"}' then return { default_face = 3, auto_switch_ms = 0 } end
  return {}
end

local text_calls = {}
local next_font_handle = 100

function lv_scr_act() return 1 end
function lv_obj_clean() end
function lv_obj_set_pos() end
function lv_canvas_create() return 2 end
function lv_canvas_frame_begin() return true end
function lv_canvas_frame_end() return true end
function lv_canvas_fill_bg() end
function lv_canvas_draw_rect() end
function lv_canvas_draw_line() end
function lv_canvas_draw_arc() end
function lv_canvas_draw_img() return true end
function lv_canvas_draw_text(canvas, x, y, max_w, value, descriptor)
  text_calls[#text_calls + 1] = {
    canvas = canvas,
    x = x,
    y = y,
    max_w = max_w,
    value = value,
    font_handle = descriptor and descriptor.font_handle,
    letter_space = descriptor and descriptor.letter_space,
  }
end
function lv_font_load()
  next_font_handle = next_font_handle + 1
  return next_font_handle
end
function lv_font_free() end

LV_IMG_CF_TRUE_COLOR = 1
LV_TEXT_ALIGN_LEFT = 0
LV_TEXT_ALIGN_CENTER = 1
LV_TEXT_ALIGN_RIGHT = 2
LV_FONT_MONTSERRAT_8 = 8
LV_FONT_MONTSERRAT_12 = 12
LV_FONT_MONTSERRAT_16 = 16
LV_FONT_MONTSERRAT_28 = 28

local expected_hour_widths = {
  [0] = 81, 63, 77, 79, 81, 78, 79, 74, 79, 79,
  63, 45, 59, 61, 63, 60, 61, 56, 61, 61,
  77, 59, 73, 75,
}

for hour = 0, 23 do
  now.hour = hour
  now.min = (hour * 7) % 60
  text_calls = {}
  dofile("NixieClock/package/main.lua")

  local target = rawget(_G, "HOLO_TIME_APP")
  assert_true(target and target.running, "app should start")
  assert_eq(target.state.face, 3, "Neon Girl face")

  local hh = string.format("%02d", now.hour)
  local mm = string.format("%02d", now.min)
  local hour_call
  local colon_call
  local minute_call
  for _, call in ipairs(text_calls) do
    if call.x == 18 and call.y == 68 and call.value == hh then hour_call = call end
    if call.y == 60 and call.value == ":" then colon_call = call end
    if call.y == 68 and call.value == mm and call.x ~= 18 then minute_call = call end
  end

  assert_true(hour_call, hh .. " hour draw call")
  assert_true(colon_call, hh .. " colon draw call")
  assert_true(minute_call, hh .. " minute draw call")
  assert_eq(colon_call.x, 18 + expected_hour_widths[hour] + 9, hh .. " colon position")
  assert_eq(minute_call.x, colon_call.x + 18, hh .. " minute position")
  assert_eq(hour_call.max_w, target.SCREEN_W - hour_call.x, hh .. " hour wrapping width")
  assert_eq(minute_call.max_w, target.SCREEN_W - minute_call.x, hh .. " minute wrapping width")
  assert_eq(hour_call.letter_space, -7, hh .. " hour glyph spacing")
  assert_eq(minute_call.letter_space, -7, hh .. " minute glyph spacing")

  target.stop("test-" .. hh)
end

print("NixieClock Neon Girl 00-23 time regression: OK")
