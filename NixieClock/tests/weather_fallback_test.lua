local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assert_true(value, message)
  if not value then error(message or "expected true") end
end

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, item in pairs(value) do copy[key] = deep_copy(item) end
  return copy
end

local cache_document
local saved_cache
local network_calls = {}
local fake_now_us = 5000000

time = {}
function time.settimezone() end
function time.initntp() end
function time.getlocal()
  return { year = 2026, mon = 7, day = 31, hour = 11, min = 15, sec = 0, wday = 6 }
end

file = {}
function file.getcontents(path)
  if path == "/sd/apps/settings.json" then return '{"kind":"settings"}' end
  if path == "/sd/apps/NixieClock/config.json" then return '{"kind":"config"}' end
  if path == "/sd/apps/NixieClock/weather-cache.json" and cache_document then return '{"kind":"cache"}' end
  return nil
end
function file.putcontents(path, raw)
  assert_eq(path, "/sd/apps/NixieClock/weather-cache.json", "weather cache path")
  assert_eq(raw, '{"kind":"encoded-cache"}', "weather cache encoding")
  return true
end

sjson = {}
function sjson.decode(raw)
  if raw == '{"kind":"settings"}' then
    return {
      timezone = "CST-8",
      weather_address = "Shenzhen",
      weather_location_id = "101280601",
      weather_city = "深圳",
    }
  end
  if raw == '{"kind":"config"}' then return { default_face = 3, auto_switch_ms = 0 } end
  if raw == '{"kind":"cache"}' then return deep_copy(cache_document) end
  if raw == '{"kind":"geocoding"}' then
    return {
      results = {
        { name = "深圳", latitude = 22.5431, longitude = 114.0579, timezone = "Asia/Shanghai" },
      },
    }
  end
  if raw == '{"kind":"open-meteo"}' then
    return {
      current = {
        temperature_2m = 28.1,
        relative_humidity_2m = 83,
        weather_code = 3,
        wind_speed_10m = 11.6,
      },
      daily = {
        time = { "2026-07-31", "2026-08-01", "2026-08-02" },
        weather_code = { 3, 61, 95 },
        temperature_2m_max = { 33, 32, 31 },
        temperature_2m_min = { 27, 26, 26 },
      },
    }
  end
  return {}
end
function sjson.encode(value)
  if type(value) == "table" and tonumber(value.schema) == 1 then
    saved_cache = deep_copy(value)
    return '{"kind":"encoded-cache"}'
  end
  return "{}"
end

http = { cubicserver = {} }
function http.cubicserver.get(path, headers, callback)
  network_calls[#network_calls + 1] = "cubic:" .. path
  callback(-1, "perform ESP_ERR_HTTP_CONNECT errno=104")
end
function http.get(url, options, callback)
  network_calls[#network_calls + 1] = "direct:" .. url
  if url:find("geocoding%-api%.open%-meteo%.com", 1, false) then
    callback(200, '{"kind":"geocoding"}')
  elseif url:find("api%.open%-meteo%.com/v1/forecast", 1, false) then
    callback(200, '{"kind":"open-meteo"}')
  else
    callback(-1, "unexpected URL")
  end
end

tmr = { ALARM_AUTO = 1, ALARM_SINGLE = 0 }
function tmr.now() return fake_now_us end
function tmr.create()
  local timer = {}
  function timer:alarm(interval, mode, callback)
    self.interval = interval
    self.mode = mode
    self.callback = callback
    return true
  end
  function timer:stop() end
  function timer:unregister() end
  return timer
end

local next_font_handle = 100
function lv_scr_act() return 1 end
function lv_obj_clean() end
function lv_obj_set_pos() end
function lv_obj_invalidate() end
function lv_canvas_create() return 2 end
function lv_canvas_frame_begin() return true end
function lv_canvas_frame_end() return true end
function lv_canvas_fill_bg() end
function lv_canvas_draw_rect() end
function lv_canvas_draw_line() end
function lv_canvas_draw_arc() end
function lv_canvas_draw_img() return true end
function lv_canvas_draw_text() end
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

dofile("NixieClock/package/main.lua")
local target = rawget(_G, "HOLO_TIME_APP")
assert_true(target and target.running, "app should start")
assert_true(target.timers.weather_start and target.timers.weather_start.callback, "weather startup timer")
assert_true(not target.state.weather_valid, "weather should start empty without cache")

target.timers.weather_start.callback()

assert_true(#network_calls == 3, "cubicserver, geocoding and forecast should be requested")
assert_true(network_calls[1]:find("cubic:/v1/weather/now", 1, true), "cubicserver should be primary")
assert_true(network_calls[2]:find("geocoding-api.open-meteo.com", 1, true), "Open-Meteo geocoding fallback")
assert_true(network_calls[3]:find("api.open-meteo.com/v1/forecast", 1, true), "Open-Meteo forecast fallback")

assert_true(target.state.weather_valid, "fallback weather valid")
assert_eq(target.state.temp, 28.1, "fallback temperature")
assert_eq(target.state.humidity, 83, "fallback humidity")
assert_eq(target.state.wind_speed, 11.6, "fallback wind")
assert_eq(target.state.weather_code, "104", "WMO overcast icon mapping")
assert_eq(target.state.weather_text, "阴", "WMO overcast text mapping")
assert_eq(target.state.weather_source, "open-meteo", "fallback source")
assert_eq(target.state.weather_last_error, "", "fallback should clear primary error")
assert_true(not target.state.weather_inflight, "weather request completed")
assert_true(not target.state.forecast_inflight, "forecast request completed")
assert_true(not target.state.open_meteo_inflight, "fallback request completed")

assert_true(target.state.forecast_valid, "fallback forecast valid")
assert_eq(#target.state.forecast_days, 3, "fallback forecast length")
assert_eq(target.state.forecast_days[1].temp_max, 33, "fallback high")
assert_eq(target.state.forecast_days[1].temp_min, 27, "fallback low")
assert_eq(target.state.forecast_days[2].text, "小雨", "rain code mapping")
assert_eq(target.state.forecast_days[3].text, "雷阵雨", "storm code mapping")

assert_true(saved_cache ~= nil, "successful fallback should persist cache")
assert_eq(saved_cache.location_key, "address=shenzhen", "stable cache location key")
assert_eq(saved_cache.source, "open-meteo", "cache source")
assert_eq(saved_cache.weather.temp, 28.1, "cached temperature")
assert_eq(#saved_cache.forecast_days, 3, "cached forecast")

target.stop("fallback-test")
cache_document = deep_copy(saved_cache)
network_calls = {}
dofile("NixieClock/package/main.lua")

local cached = rawget(_G, "HOLO_TIME_APP")
assert_true(cached and cached.running, "cached app should start")
assert_true(cached.state.weather_valid, "cached weather should load before network")
assert_eq(cached.state.temp, 28.1, "cached temperature should survive reload")
assert_eq(cached.state.weather_source, "cache:open-meteo", "cached source")
assert_true(cached.state.forecast_valid, "cached forecast should survive reload")
assert_eq(#network_calls, 0, "startup should not request until timer fires")

function http.get(url, options, callback)
  network_calls[#network_calls + 1] = "direct-failure:" .. url
  callback(-1, "offline")
end
cached.timers.weather_start.callback()
assert_true(cached.state.weather_valid, "failed refresh must retain cached weather")
assert_eq(cached.state.temp, 28.1, "failed refresh must retain cached temperature")
assert_true(cached.state.forecast_valid, "failed refresh must retain cached forecast")
assert_eq(cached.state.weather_last_error, "offline", "failed refresh diagnostic")
assert_true(not cached.state.weather_inflight, "failed refresh should complete")
cached.stop("cache-test")

print("NixieClock weather fallback and persistent cache regression: OK")
