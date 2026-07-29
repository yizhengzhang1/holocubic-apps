---@meta

-- 由 tools/gen_luals_meta.py 生成，请勿手改。
-- 这些全局由固件（Lua 运行时 / LVGL 绑定）注入，仓库里没有定义。
-- 类型故意留得很宽：目的是消掉 undefined-global 噪音、保住拼写检查与补全，
-- 不是描述真实签名。某个 API 的签名确定后，可以在这里手工细化并从生成器里排除。

-- 固件模块 / 服务（22 个）
---@type any
app = nil

---@type any
controller = nil

---@type any
file = nil

---@type any
gamepad = nil

---@type any
http = nil

---@type any
httpd = nil

---@type any
i2s = nil

---@type any
ipc = nil

---@type any
json = nil

---@type any
key = nil

---@type fun(...):any
millis = nil

---@type any
net = nil

---@type any
rtctime = nil

---@type any
service_ui = nil

---@type any
sjson = nil

---@type fun(...):any
sleep = nil

---@type any
sys = nil

---@type any
time = nil

---@type any
tmr = nil

---@type any
websocket = nil

---@type any
wifi = nil

---@type any
zlib = nil

-- LVGL 绑定函数（108 个）
---@type fun(...):any
lv_anim_del = nil

---@type fun(...):any
lv_anim_get_user_data = nil

---@type fun(...):any
lv_anim_init = nil

---@type any
lv_anim_path_ease_in_out = nil

---@type any
lv_anim_path_ease_out = nil

---@type fun(...):any
lv_anim_set_custom_exec_cb = nil

---@type fun(...):any
lv_anim_set_delay = nil

---@type fun(...):any
lv_anim_set_exec_cb = nil

---@type fun(...):any
lv_anim_set_path_cb = nil

---@type fun(...):any
lv_anim_set_time = nil

---@type fun(...):any
lv_anim_set_user_data = nil

---@type fun(...):any
lv_anim_set_values = nil

---@type fun(...):any
lv_anim_set_var = nil

---@type fun(...):any
lv_anim_start = nil

---@type fun(...):any
lv_anim_t = nil

---@type fun(...):any
lv_begin = nil

---@type fun(...):any
lv_btn_create = nil

---@type fun(...):any
lv_canvas_begin = nil

---@type any
lv_canvas_blit_rgb565 = nil

---@type fun(...):any
lv_canvas_blur_hor = nil

---@type fun(...):any
lv_canvas_blur_ver = nil

---@type fun(...):any
lv_canvas_create = nil

---@type any
lv_canvas_draw_arc = nil

---@type fun(...):any
lv_canvas_draw_img = nil

---@type fun(...):any
lv_canvas_draw_line = nil

---@type fun(...):any
lv_canvas_draw_rect = nil

---@type fun(...):any
lv_canvas_draw_text = nil

---@type fun(...):any
lv_canvas_end = nil

---@type any
lv_canvas_fill = nil

---@type fun(...):any
lv_canvas_fill_bg = nil

---@type fun(...):any
lv_canvas_frame_begin = nil

---@type fun(...):any
lv_canvas_frame_end = nil

---@type fun(...):any
lv_clear = nil

---@type fun(...):any
lv_end = nil

---@type fun(...):any
lv_font_free = nil

---@type fun(...):any
lv_font_load = nil

---@type fun(...):any
lv_gif_create = nil

---@type fun(...):any
lv_gif_set_src = nil

---@type fun(...):any
lv_img_create = nil

---@type fun(...):any
lv_img_free_handle = nil

---@type fun(...):any
lv_img_set_antialias = nil

---@type fun(...):any
lv_img_set_pivot = nil

---@type fun(...):any
lv_img_set_size_mode = nil

---@type fun(...):any
lv_img_set_src = nil

---@type fun(...):any
lv_img_set_zoom = nil

---@type fun(...):any
lv_label_create = nil

---@type fun(...):any
lv_label_set_long_mode = nil

---@type fun(...):any
lv_label_set_text = nil

---@type fun(...):any
lv_obj_add_event_cb = nil

---@type fun(...):any
lv_obj_add_flag = nil

---@type fun(...):any
lv_obj_align = nil

---@type fun(...):any
lv_obj_center = nil

---@type fun(...):any
lv_obj_clean = nil

---@type fun(...):any
lv_obj_clear_flag = nil

---@type fun(...):any
lv_obj_create = nil

---@type fun(...):any
lv_obj_del = nil

---@type fun(...):any
lv_obj_invalidate = nil

---@type fun(...):any
lv_obj_move_foreground = nil

---@type fun(...):any
lv_obj_remove_event_dsc = nil

---@type fun(...):any
lv_obj_scroll_to_view_recursive = nil

---@type fun(...):any
lv_obj_scroll_to_y = nil

---@type fun(...):any
lv_obj_set_align = nil

---@type fun(...):any
lv_obj_set_height = nil

---@type any
lv_obj_set_layout = nil

---@type fun(...):any
lv_obj_set_pos = nil

---@type fun(...):any
lv_obj_set_scroll_dir = nil

---@type fun(...):any
lv_obj_set_size = nil

---@type fun(...):any
lv_obj_set_style_bg_color = nil

---@type fun(...):any
lv_obj_set_style_bg_grad_color = nil

---@type fun(...):any
lv_obj_set_style_bg_grad_dir = nil

---@type fun(...):any
lv_obj_set_style_bg_grad_stop = nil

---@type fun(...):any
lv_obj_set_style_bg_main_stop = nil

---@type fun(...):any
lv_obj_set_style_bg_opa = nil

---@type fun(...):any
lv_obj_set_style_border_color = nil

---@type fun(...):any
lv_obj_set_style_border_opa = nil

---@type fun(...):any
lv_obj_set_style_border_post = nil

---@type fun(...):any
lv_obj_set_style_border_width = nil

---@type fun(...):any
lv_obj_set_style_clip_corner = nil

---@type fun(...):any
lv_obj_set_style_img_opa = nil

---@type fun(...):any
lv_obj_set_style_opa = nil

---@type fun(...):any
lv_obj_set_style_pad_all = nil

---@type fun(...):any
lv_obj_set_style_radius = nil

---@type fun(...):any
lv_obj_set_style_shadow_color = nil

---@type fun(...):any
lv_obj_set_style_shadow_ofs_x = nil

---@type fun(...):any
lv_obj_set_style_shadow_ofs_y = nil

---@type fun(...):any
lv_obj_set_style_shadow_opa = nil

---@type fun(...):any
lv_obj_set_style_shadow_spread = nil

---@type fun(...):any
lv_obj_set_style_shadow_width = nil

---@type fun(...):any
lv_obj_set_style_text_align = nil

---@type fun(...):any
lv_obj_set_style_text_color = nil

---@type fun(...):any
lv_obj_set_style_text_font = nil

---@type fun(...):any
lv_obj_set_style_text_letter_space = nil

---@type fun(...):any
lv_obj_set_style_text_opa = nil

---@type fun(...):any
lv_obj_set_width = nil

---@type fun(...):any
lv_obj_set_x = nil

---@type fun(...):any
lv_obj_set_y = nil

---@type fun(...):any
lv_obj_update_layout = nil

---@type fun(...):any
lv_refr_now = nil

---@type fun(...):any
lv_scr_act = nil

---@type any
lv_scr_load = nil

---@type fun(...):any
lv_slider_create = nil

---@type fun(...):any
lv_slider_get_value = nil

---@type fun(...):any
lv_slider_set_range = nil

---@type fun(...):any
lv_slider_set_value = nil

---@type fun(...):any
lv_snapshot_free = nil

---@type fun(...):any
lv_snapshot_take = nil

---@type any
lv_task_handler = nil

---@type any
lv_timer_handler = nil

-- LVGL 常量（25 个）
---@type any
LV_ALIGN_BOTTOM_LEFT = nil

---@type any
LV_ALIGN_BOTTOM_MID = nil

---@type any
LV_ALIGN_BOTTOM_RIGHT = nil

---@type any
LV_ALIGN_CENTER = nil

---@type any
LV_ALIGN_TOP_LEFT = nil

---@type any
LV_ALIGN_TOP_MID = nil

---@type any
LV_ALIGN_TOP_RIGHT = nil

---@type any
LV_FONT_MONTSERRAT_12 = nil

---@type any
LV_FONT_MONTSERRAT_14 = nil

---@type any
LV_FONT_MONTSERRAT_16 = nil

---@type any
LV_FONT_MONTSERRAT_20 = nil

---@type any
LV_GRAD_DIR_VER = nil

---@type any
LV_IMG_CF_TRUE_COLOR = nil

---@type any
LV_IMG_SIZE_MODE_REAL = nil

---@type any
LV_LABEL_LONG_CLIP = nil

---@type any
LV_OBJ_FLAG_CLICKABLE = nil

---@type any
LV_OBJ_FLAG_HIDDEN = nil

---@type any
LV_OBJ_FLAG_OVERFLOW_VISIBLE = nil

---@type any
LV_OBJ_FLAG_SCROLLABLE = nil

---@type any
LV_PART_MAIN = nil

---@type any
LV_SIZE_CONTENT = nil

---@type any
LV_STATE_DEFAULT = nil

---@type any
LV_TEXT_ALIGN_CENTER = nil

---@type any
LV_TEXT_ALIGN_LEFT = nil

---@type any
LV_TEXT_ALIGN_RIGHT = nil
