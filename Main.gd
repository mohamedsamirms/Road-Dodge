extends Node2D

var SCREEN_W := 400.0
var SCREEN_H := 700.0
var ROAD_LEFT := 100.0
var ROAD_RIGHT := 300.0
const LANE_COUNT := 3
var LANE_WIDTH := 66.6667
var ui_scale := 1.0
var tree_spacing := 140.0
var effective_scroll_speed := 220.0

var PLAYER_Y := 580.0
const LANE_MOVE_SPEED := 12.0
var player_lane := 1
var player_x := 0.0

var score := 0.0
var scroll_offset := 0.0
const SCROLL_SPEED := 220.0
var shield_active := false

var entities := []
var next_id := 0
var spawn_timer := 0.0
var spawn_interval := 0.9

var trees := []

const ICON_PATH := "res://icon.svg"
var player_texture: Texture2D = null

const SAVE_PATH := "user://savegame.json"
var high_score := 0
var coins := 0
var upg_shield := 0
var upg_multiplier := 0
var upg_headstart := 0

const MULT_STEP := 0.1
const MULT_MAX := 5
const HEADSTART_STEP := 0.2
const HEADSTART_MAX := 3
const SHIELD_COST := 40
const MULT_BASE_COST := 20
const HEADSTART_BASE_COST := 15

enum GameState { LOADING, MENU, SHOP, PLAYING, GAME_OVER }
var state := GameState.LOADING
var loading_timer := 0.0
const LOADING_DURATION := 1.3

var sfx_coin: AudioStreamPlayer
var sfx_crash: AudioStreamPlayer
var sfx_switch: AudioStreamPlayer
var sfx_upgrade: AudioStreamPlayer
var sfx_shield: AudioStreamPlayer

const DISCORD_URL := "https://discord.gg/xVbqpgH2GX"

func score_multiplier() -> float:
	return 1.0 + upg_multiplier * MULT_STEP

func shield_cost() -> int:
	return SHIELD_COST

func mult_cost() -> int:
	return MULT_BASE_COST * (upg_multiplier + 1)

func headstart_cost() -> int:
	return HEADSTART_BASE_COST * (upg_headstart + 1)

func _ready() -> void:
	randomize()
	get_window().mode = Window.MODE_FULLSCREEN
	get_window().size_changed.connect(_update_layout)
	_update_layout()

	trees.clear()
	for i in range(6):
		trees.append({"y": i * tree_spacing - 100.0, "side": i % 2})

	load_game()

	if ResourceLoader.exists(ICON_PATH):
		player_texture = load(ICON_PATH)

	sfx_coin = make_player("res://sfx/coin.wav")
	sfx_crash = make_player("res://sfx/crash.wav")
	sfx_switch = make_player("res://sfx/switch.wav")
	sfx_upgrade = make_player("res://sfx/upgrade.wav")
	sfx_shield = make_player("res://sfx/shield.wav")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_update_layout()

func make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()

	if ResourceLoader.exists(path):
		p.stream = load(path)

	add_child(p)
	return p

func play_sfx(p: AudioStreamPlayer) -> void:
	if p and p.stream:
		p.play()

func _update_layout() -> void:
	var vp := get_viewport_rect().size

	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	SCREEN_W = vp.x
	SCREEN_H = vp.y
	ui_scale = clamp(min(SCREEN_W, SCREEN_H) / 400.0, 0.7, 2.5)

	var road_width: float = clamp(SCREEN_W * 0.5, 240.0, 560.0)
	ROAD_LEFT = (SCREEN_W - road_width) / 2.0
	ROAD_RIGHT = ROAD_LEFT + road_width
	LANE_WIDTH = road_width / LANE_COUNT

	PLAYER_Y = SCREEN_H * 0.83
	tree_spacing = max(120.0, SCREEN_H * 0.2)
	effective_scroll_speed = SCROLL_SPEED * (SCREEN_H / 700.0)

	player_x = lane_center(player_lane)
	queue_redraw()

func content_width() -> float:
	return min(SCREEN_W * 0.85, 480.0)

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)

	if not f:
		return

	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)

	if typeof(parsed) == TYPE_DICTIONARY:
		high_score = int(parsed.get("high_score", 0))
		coins = int(parsed.get("coins", 0))
		upg_shield = int(parsed.get("upg_shield", 0))
		upg_multiplier = int(parsed.get("upg_multiplier", 0))
		upg_headstart = int(parsed.get("upg_headstart", 0))
	else:
		high_score = text.strip_edges().to_int()

func save_game() -> void:
	var data := {
		"high_score": high_score,
		"coins": coins,
		"upg_shield": upg_shield,
		"upg_multiplier": upg_multiplier,
		"upg_headstart": upg_headstart
	}

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func lane_center(lane: int) -> float:
	return ROAD_LEFT + LANE_WIDTH * (lane + 0.5)

func buy_shield() -> void:
	if upg_shield < 1 and coins >= shield_cost():
		coins -= shield_cost()
		upg_shield = 1
		save_game()
		play_sfx(sfx_upgrade)

func buy_multiplier() -> void:
	if upg_multiplier < MULT_MAX and coins >= mult_cost():
		coins -= mult_cost()
		upg_multiplier += 1
		save_game()
		play_sfx(sfx_upgrade)

func buy_headstart() -> void:
	if upg_headstart < HEADSTART_MAX and coins >= headstart_cost():
		coins -= headstart_cost()
		upg_headstart += 1
		save_game()
		play_sfx(sfx_upgrade)

func _unhandled_input(event: InputEvent) -> void:
	var keycode: int = event.keycode if (event is InputEventKey and event.pressed) else -1
	var tap_pos: Variant = _get_tap_pos(event)
	
	if tap_pos != null and state != GameState.PLAYING and discord_icon_rect().has_point(tap_pos):
		open_discord()
		return

	match state:
		GameState.MENU:
			if keycode == KEY_SPACE or keycode == KEY_ENTER:
				start_run()
			elif keycode == KEY_S:
				state = GameState.SHOP
			elif tap_pos != null:
				if menu_shop_rect().has_point(tap_pos):
					state = GameState.SHOP
				elif menu_play_rect().has_point(tap_pos):
					start_run()

		GameState.SHOP:
			var shop_actions := [buy_shield, buy_multiplier, buy_headstart]
			if keycode in [KEY_1, KEY_2, KEY_3]:
				shop_actions[keycode - KEY_1].call()
			elif keycode == KEY_ESCAPE or keycode == KEY_SPACE:
				state = GameState.MENU
			elif tap_pos != null:
				if shop_back_rect().has_point(tap_pos):
					state = GameState.MENU
				else:
					for i in shop_actions.size():
						if shop_row_rect(i).has_point(tap_pos):
							shop_actions[i].call()
							break

		GameState.PLAYING:
			var dir := 0
			if keycode == KEY_LEFT or keycode == KEY_A:
				dir = -1
			elif keycode == KEY_RIGHT or keycode == KEY_D:
				dir = 1
			elif tap_pos != null:
				dir = -1 if tap_pos.x < SCREEN_W / 2.0 else 1
			_try_switch_lane(dir)

		GameState.GAME_OVER:
			if keycode != -1 or tap_pos != null:
				state = GameState.MENU


func _get_tap_pos(event: InputEvent) -> Variant:
	if event is InputEventScreenTouch and event.pressed:
		return event.position
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return event.position
	return null


func _try_switch_lane(dir: int) -> void:
	if dir == 0:
		return
	var new_lane := player_lane + dir
	if new_lane >= 0 and new_lane < LANE_COUNT:
		player_lane = new_lane
		play_sfx(sfx_switch)

func open_discord() -> void:
	OS.shell_open(DISCORD_URL)

func discord_icon_rect() -> Rect2:
	var s := 34.0 * ui_scale
	return Rect2(
		SCREEN_W - s - 14.0 * ui_scale,
		14.0 * ui_scale,
		s,
		s
	)

func menu_play_rect() -> Rect2:
	var w := content_width() * 0.6
	var h := SCREEN_H * 0.065

	return Rect2(
		SCREEN_W / 2.0 - w / 2.0,
		SCREEN_H * 0.56,
		w,
		h
	)

func menu_shop_rect() -> Rect2:
	var w := content_width() * 0.6
	var h := SCREEN_H * 0.065

	return Rect2(
		SCREEN_W / 2.0 - w / 2.0,
		SCREEN_H * 0.645,
		w,
		h
	)

func shop_row_rect(index: int) -> Rect2:
	var w := content_width()
	var h := SCREEN_H * 0.105
	var top := SCREEN_H * 0.27
	var gap := SCREEN_H * 0.135

	return Rect2(
		SCREEN_W / 2.0 - w / 2.0,
		top + index * gap,
		w,
		h
	)

func shop_back_rect() -> Rect2:
	var w := content_width() * 0.42
	var h := SCREEN_H * 0.06

	return Rect2(
		SCREEN_W / 2.0 - w / 2.0,
		SCREEN_H - h - SCREEN_H * 0.04,
		w,
		h
	)

func start_run() -> void:
	score = 0.0
	shield_active = upg_shield >= 1
	entities.clear()
	player_lane = 1
	player_x = lane_center(player_lane)
	spawn_timer = 0.0
	spawn_interval = 0.9 + upg_headstart * HEADSTART_STEP
	state = GameState.PLAYING

func _process(delta: float) -> void:
	match state:
		GameState.LOADING:
			loading_timer += delta

			if loading_timer >= LOADING_DURATION:
				state = GameState.MENU

		GameState.PLAYING:
			_process_gameplay(delta)

	queue_redraw()

func _process_gameplay(delta: float) -> void:
	var mult := score_multiplier()
	score += delta * 10.0 * mult
	scroll_offset = fmod(scroll_offset + effective_scroll_speed * delta, 100000.0)

	player_x = lerp(player_x, lane_center(player_lane), delta * LANE_MOVE_SPEED)

	_update_spawning(delta)
	_update_entities(delta, mult)
	_update_trees(delta)


func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = spawn_interval
	spawn_interval = max(0.45, spawn_interval - 0.01)

	var roll: float = randf()
	var e_type := "car"
	if roll < 0.25:
		e_type = "coin"
	elif roll < 0.4:
		e_type = "cow"

	entities.append({
		"id": next_id,
		"y": -40.0,
		"lane": randi() % LANE_COUNT,
		"type": e_type
	})
	next_id += 1


func _update_entities(delta: float, mult: float) -> void:
	var move: float = effective_scroll_speed * delta
	var hit_range: float = 18.0 * ui_scale
	var kept: Array = []
	kept.resize(entities.size())
	var kept_count := 0

	for e in entities:
		e.y += move

		if abs(e.y - PLAYER_Y) < hit_range and e.lane == player_lane:
			if e.type == "coin":
				score += 50.0 * mult
				coins += 1
				play_sfx(sfx_coin)
				continue
			elif shield_active:
				shield_active = false
				play_sfx(sfx_shield)
				continue
			else:
				end_run()
				return

		if e.y <= SCREEN_H + 40.0:
			kept[kept_count] = e
			kept_count += 1

	kept.resize(kept_count)
	entities = kept


func _update_trees(delta: float) -> void:
	var move: float = effective_scroll_speed * delta
	var wrap_offset: float = trees.size() * tree_spacing
	for t in trees:
		t.y += move
		if t.y > SCREEN_H + 60.0:
			t.y -= wrap_offset

func end_run() -> void:
	state = GameState.GAME_OVER
	play_sfx(sfx_crash)

	if int(score) > high_score:
		high_score = int(score)

	save_game()

func _draw() -> void:
	var font := ThemeDB.fallback_font

	match state:
		GameState.LOADING:
			draw_loading_screen(font)
		GameState.MENU:
			draw_road_background()
			draw_menu_screen(font)
		GameState.SHOP:
			draw_road_background()
			draw_shop_screen(font)
		GameState.PLAYING:
			draw_road_background()
			draw_entities()
			draw_godot_character(Vector2(player_x, PLAYER_Y), false)
			draw_hud(font)
		GameState.GAME_OVER:
			draw_road_background()
			draw_entities()
			draw_godot_character(Vector2(player_x, PLAYER_Y), true)
			draw_hud(font)
			draw_gameover_screen(font)

func draw_shadow(pos: Vector2, radius: float, alpha: float = 0.25) -> void:
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_button(rect: Rect2, text: String, font: Font, color: Color, font_size: float) -> void:
	draw_rect(
		Rect2(rect.position + Vector2(0, 3.0 * ui_scale), rect.size),
		Color(0, 0, 0, 0.25)
	)
	draw_rect(rect, color)
	draw_rect(rect, Color(1, 1, 1, 0.08), false, 1.5 * ui_scale)

	var text_size := font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	)

	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)

	var pos := Vector2(
		rect.position.x + (rect.size.x - text_size.x) / 2.0,
		rect.position.y + (rect.size.y - ascent - descent) / 2.0 + ascent
	)

	draw_string(
		font,
		pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(1, 1, 1)
	)

func draw_centered_text(font: Font, y: float, text: String, size: float, color: Color) -> void:
	var width := font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size
	).x

	var ascent := font.get_ascent(size)

	draw_string(
		font,
		Vector2(SCREEN_W / 2.0 - width / 2.0, y + ascent),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		color
	)

func draw_road_background() -> void:
	draw_rect(
		Rect2(0, 0, SCREEN_W, SCREEN_H),
		Color(0.56, 0.73, 0.36)
	)

	var stripe_h := 70.0 * ui_scale
	var stripe_period := stripe_h * 2.0
	var sy := fmod(scroll_offset * (stripe_h / 20.0), stripe_period) - stripe_period

	while sy < SCREEN_H:
		draw_rect(
			Rect2(0, sy, ROAD_LEFT, stripe_h),
			Color(0.51, 0.69, 0.33)
		)

		draw_rect(
			Rect2(ROAD_RIGHT, sy, SCREEN_W - ROAD_RIGHT, stripe_h),
			Color(0.51, 0.69, 0.33)
		)

		sy += stripe_period

	draw_rect(
		Rect2(ROAD_LEFT, 0, ROAD_RIGHT - ROAD_LEFT, SCREEN_H),
		Color(0.21, 0.21, 0.24)
	)

	draw_rect(
		Rect2(ROAD_LEFT, 0, 12.0 * ui_scale, SCREEN_H),
		Color(0, 0, 0, 0.12)
	)

	draw_rect(
		Rect2(ROAD_RIGHT - 12.0 * ui_scale, 0, 12.0 * ui_scale, SCREEN_H),
		Color(0, 0, 0, 0.12)
	)

	draw_rect(
		Rect2(ROAD_LEFT - 5.0 * ui_scale, 0, 5.0 * ui_scale, SCREEN_H),
		Color(0.95, 0.8, 0.1)
	)

	draw_rect(
		Rect2(ROAD_RIGHT, 0, 5.0 * ui_scale, SCREEN_H),
		Color(0.95, 0.8, 0.1)
	)

	var dash_len := 46.0 * ui_scale
	var gap := 30.0 * ui_scale
	var dash_width := 6.0 * ui_scale
	var dash_period := dash_len + gap

	for lane_i in range(1, LANE_COUNT):
		var lx := ROAD_LEFT + LANE_WIDTH * lane_i
		var dy := fmod(scroll_offset, dash_period) - dash_period

		while dy < SCREEN_H:
			draw_rect(
				Rect2(
					lx - dash_width / 2.0,
					dy,
					dash_width,
					dash_len
				),
				Color(1, 1, 1, 0.6)
			)

			dy += dash_period

	for t in trees:
		var tx := ROAD_LEFT * 0.5 if t.side == 0 else ROAD_RIGHT + (SCREEN_W - ROAD_RIGHT) * 0.5
		draw_tree(Vector2(tx, t.y))

func draw_entities() -> void:
	for e in entities:
		var ex := lane_center(e.lane)

		if e.type == "car":
			draw_car(Vector2(ex, e.y))
		elif e.type == "coin":
			draw_coin(Vector2(ex, e.y))
		elif e.type == "cow":
			draw_cow(Vector2(ex, e.y))

func draw_hud(font: Font) -> void:
	var pad := 10.0 * ui_scale

	draw_rect(
		Rect2(
			pad - 8.0 * ui_scale,
			pad - 8.0 * ui_scale,
			165.0 * ui_scale,
			84.0 * ui_scale
		),
		Color(0, 0, 0, 0.3)
	)

	var score_size := 18.0 * ui_scale
	var small_size := 14.0 * ui_scale

	draw_string(
		font,
		Vector2(pad, pad + font.get_ascent(score_size)),
		"Score: %d" % int(score),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		score_size,
		Color(1, 1, 1)
	)

	draw_string(
		font,
		Vector2(pad, pad + 23.0 * ui_scale + font.get_ascent(small_size)),
		"Best: %d" % high_score,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		small_size,
		Color(1, 0.85, 0.2)
	)

	draw_string(
		font,
		Vector2(pad, pad + 44.0 * ui_scale + font.get_ascent(small_size)),
		"Coins: %d" % coins,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		small_size,
		Color(0.6, 0.9, 1)
	)

	if shield_active:
		var d_rect := discord_icon_rect()
		var shield_text := "SHIELD"
		var sfs := 14.0 * ui_scale
		var sw := font.get_string_size(
			shield_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			sfs
		).x

		var badge := Rect2(
			SCREEN_W - sw - 20.0 * ui_scale,
			d_rect.position.y + d_rect.size.y + 8.0 * ui_scale,
			sw + 16.0 * ui_scale,
			24.0 * ui_scale
		)

		draw_rect(badge, Color(0.15, 0.35, 0.5, 0.6))

		draw_string(
			font,
			Vector2(
				badge.position.x + 8.0 * ui_scale,
				badge.position.y + (badge.size.y - font.get_ascent(sfs) - font.get_descent(sfs)) / 2.0 + font.get_ascent(sfs)
			),
			shield_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			sfs,
			Color(0.6, 0.88, 1)
		)

	if state == GameState.PLAYING:
		draw_centered_text(
			font,
			SCREEN_H - 30.0 * ui_scale,
			"<- tap / A,D / arrows ->",
			13.0 * ui_scale,
			Color(1, 1, 1, 0.65)
		)

func draw_loading_screen(font: Font) -> void:
	draw_rect(
		Rect2(0, 0, SCREEN_W, SCREEN_H),
		Color(0.13, 0.14, 0.17)
	)

	draw_godot_character(
		Vector2(
			SCREEN_W / 2.0,
			SCREEN_H / 2.0 - 60.0 * ui_scale
		),
		false
	)

	draw_centered_text(
		font,
		SCREEN_H / 2.0 + 10.0 * ui_scale,
		"ROAD DODGE",
		28.0 * ui_scale,
		Color(1, 1, 1)
	)

	var bar_w: float = min(SCREEN_W * 0.6, 260.0)
	var bar_h := 14.0 * ui_scale
	var bar_x := SCREEN_W / 2.0 - bar_w / 2.0
	var bar_y := SCREEN_H / 2.0 + 50.0 * ui_scale

	draw_rect(
		Rect2(bar_x, bar_y, bar_w, bar_h),
		Color(0.3, 0.3, 0.34)
	)

	var pct: float = clamp(
		loading_timer / LOADING_DURATION,
		0.0,
		1.0
	)

	draw_rect(
		Rect2(bar_x, bar_y, bar_w * pct, bar_h),
		Color(0.28, 0.55, 0.75)
	)

	draw_centered_text(
		font,
		bar_y + bar_h + 12.0 * ui_scale,
		"Loading...",
		14.0 * ui_scale,
		Color(0.8, 0.8, 0.85)
	)

func draw_menu_screen(font: Font) -> void:
	draw_rect(
		Rect2(0, 0, SCREEN_W, SCREEN_H),
		Color(0, 0, 0, 0.45)
	)

	draw_godot_character(
		Vector2(SCREEN_W / 2.0, SCREEN_H * 0.32),
		false
	)

	draw_centered_text(
		font,
		SCREEN_H * 0.44,
		"ROAD DODGE",
		30.0 * ui_scale,
		Color(1, 1, 1)
	)

	draw_centered_text(
		font,
		SCREEN_H * 0.44 + 34.0 * ui_scale,
		"Best: %d   Coins: %d" % [high_score, coins],
		15.0 * ui_scale,
		Color(1, 0.85, 0.2)
	)

	draw_button(
		menu_play_rect(),
		"PLAY",
		font,
		Color(0.28, 0.55, 0.75),
		19.0 * ui_scale
	)

	draw_button(
		menu_shop_rect(),
		"UPGRADES",
		font,
		Color(0.3, 0.3, 0.34),
		16.0 * ui_scale
	)

	draw_centered_text(
		font,
		SCREEN_H * 0.645 + SCREEN_H * 0.065 + 20.0 * ui_scale,
		"Tap, or SPACE / S on keyboard",
		13.0 * ui_scale,
		Color(0.85, 0.85, 0.85)
	)

	draw_discord_icon(discord_icon_rect())

func draw_shop_screen(font: Font) -> void:
	draw_rect(
		Rect2(0, 0, SCREEN_W, SCREEN_H),
		Color(0, 0, 0, 0.62)
	)

	draw_centered_text(
		font,
		SCREEN_H * 0.12,
		"UPGRADES",
		26.0 * ui_scale,
		Color(1, 1, 1)
	)

	draw_centered_text(
		font,
		SCREEN_H * 0.12 + 30.0 * ui_scale,
		"Coins: %d" % coins,
		16.0 * ui_scale,
		Color(0.6, 0.9, 1)
	)

	var rows := [
		{
			"rect": shop_row_rect(0),
			"title": "[1] Shield - absorb one hit per run",
			"status": "OWNED" if upg_shield >= 1 else "Cost: %d" % shield_cost(),
			"col": Color(0.4, 1, 0.5) if upg_shield >= 1 else Color(1, 0.85, 0.4)
		},
		{
			"rect": shop_row_rect(1),
			"title": "[2] Score Boost - Lv %d/%d (+%d%%)" % [
				upg_multiplier,
				MULT_MAX,
				int(upg_multiplier * MULT_STEP * 100)
			],
			"status": "MAX LEVEL" if upg_multiplier >= MULT_MAX else "Cost: %d" % mult_cost(),
			"col": Color(1, 0.85, 0.4)
		},
		{
			"rect": shop_row_rect(2),
			"title": "[3] Head Start - Lv %d/%d (easier start)" % [
				upg_headstart,
				HEADSTART_MAX
			],
			"status": "MAX LEVEL" if upg_headstart >= HEADSTART_MAX else "Cost: %d" % headstart_cost(),
			"col": Color(0.6, 0.9, 1)
		}
	]

	for row in rows:
		var r: Rect2 = row["rect"]
		var title_size := 15.0 * ui_scale
		var status_size := 14.0 * ui_scale

		draw_rect(
			Rect2(
				r.position + Vector2(0, 3.0 * ui_scale),
				r.size
			),
			Color(0, 0, 0, 0.2)
		)

		draw_rect(
			r,
			Color(0.18, 0.18, 0.22)
		)

		var title_y := r.position.y + r.size.y * 0.35
		var status_y := r.position.y + r.size.y * 0.67

		draw_string(
			font,
			Vector2(
				r.position.x + 14.0 * ui_scale,
				title_y + font.get_ascent(title_size)
			),
			row["title"],
			HORIZONTAL_ALIGNMENT_LEFT,
			int(r.size.x - 24.0 * ui_scale),
			title_size,
			Color(1, 1, 1)
		)

		draw_string(
			font,
			Vector2(
				r.position.x + 14.0 * ui_scale,
				status_y + font.get_ascent(status_size)
			),
			row["status"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			status_size,
			row["col"]
		)

	draw_button(
		shop_back_rect(),
		"BACK",
		font,
		Color(0.3, 0.3, 0.34),
		16.0 * ui_scale
	)

	draw_discord_icon(discord_icon_rect())

func draw_gameover_screen(font: Font) -> void:
	draw_rect(
		Rect2(0, 0, SCREEN_W, SCREEN_H),
		Color(0, 0, 0, 0.55)
	)

	draw_sad_face(
		Vector2(
			SCREEN_W / 2.0,
			SCREEN_H / 2.0 - 70.0 * ui_scale
		)
	)

	draw_centered_text(
		font,
		SCREEN_H / 2.0 + 10.0 * ui_scale,
		"GAME OVER",
		28.0 * ui_scale,
		Color(1, 1, 1)
	)

	draw_centered_text(
		font,
		SCREEN_H / 2.0 + 45.0 * ui_scale,
		"Score: %d" % int(score),
		20.0 * ui_scale,
		Color(1, 1, 1)
	)

	var best_col := Color(1, 0.85, 0.2) if int(score) < high_score else Color(0.3, 1, 0.4)
	var best_label := "Best: %d" % high_score if int(score) < high_score else "NEW BEST: %d" % high_score

	draw_centered_text(
		font,
		SCREEN_H / 2.0 + 72.0 * ui_scale,
		best_label,
		18.0 * ui_scale,
		best_col
	)

	draw_centered_text(
		font,
		SCREEN_H / 2.0 + 105.0 * ui_scale,
		"Press any key to continue",
		16.0 * ui_scale,
		Color(0.9, 0.9, 0.9)
	)

	draw_discord_icon(discord_icon_rect())

func draw_tree(pos: Vector2) -> void:
	draw_shadow(
		pos + Vector2(0, 8.0 * ui_scale),
		14.0 * ui_scale,
		0.2
	)

	draw_rect(
		Rect2(
			pos.x - 3.0 * ui_scale,
			pos.y - 4.0 * ui_scale,
			6.0 * ui_scale,
			22.0 * ui_scale
		),
		Color(0.38, 0.24, 0.1)
	)

	draw_circle(
		pos + Vector2(0, -12.0 * ui_scale),
		17.0 * ui_scale,
		Color(0.16, 0.5, 0.21)
	)

	draw_circle(
		pos + Vector2(-5.0 * ui_scale, -18.0 * ui_scale),
		11.0 * ui_scale,
		Color(0.24, 0.62, 0.28)
	)

func draw_car(pos: Vector2) -> void:
	var w := 28.0 * ui_scale
	var h := 44.0 * ui_scale

	draw_shadow(
		pos + Vector2(0, h * 0.5),
		w * 0.6,
		0.22
	)

	draw_rect(
		Rect2(
			pos.x - w / 2.0,
			pos.y - h / 2.0,
			w,
			h
		),
		Color(0.82, 0.16, 0.16)
	)

	draw_rect(
		Rect2(
			pos.x - w / 2.0 + w * 0.12,
			pos.y - h / 2.0 + h * 0.14,
			w - w * 0.24,
			h * 0.26
		),
		Color(0.65, 0.87, 0.96)
	)

	draw_rect(
		Rect2(
			pos.x - w / 2.0 + w * 0.12,
			pos.y + h * 0.06,
			w - w * 0.24,
			h * 0.2
		),
		Color(0.65, 0.87, 0.96, 0.75)
	)

	var wheel_r := 4.0 * ui_scale

	draw_circle(
		pos + Vector2(-w / 2.0, h / 2.0 - wheel_r),
		wheel_r,
		Color(0.05, 0.05, 0.05)
	)

	draw_circle(
		pos + Vector2(w / 2.0, h / 2.0 - wheel_r),
		wheel_r,
		Color(0.05, 0.05, 0.05)
	)

	draw_circle(
		pos + Vector2(-w / 2.0, -h / 2.0 + wheel_r),
		wheel_r,
		Color(0.05, 0.05, 0.05)
	)

	draw_circle(
		pos + Vector2(w / 2.0, -h / 2.0 + wheel_r),
		wheel_r,
		Color(0.05, 0.05, 0.05)
	)

func draw_coin(pos: Vector2) -> void:
	draw_shadow(
		pos + Vector2(0, 7.0 * ui_scale),
		8.0 * ui_scale,
		0.18
	)

	draw_circle(
		pos,
		9.0 * ui_scale,
		Color(0.95, 0.85, 0.2)
	)

	draw_arc(
		pos,
		9.0 * ui_scale,
		0,
		TAU,
		16,
		Color(0.6, 0.5, 0.05),
		2.0 * ui_scale
	)

	draw_circle(
		pos + Vector2(-2.5 * ui_scale, -2.5 * ui_scale),
		2.4 * ui_scale,
		Color(1, 1, 0.85, 0.85)
	)

func draw_cow(pos: Vector2) -> void:
	draw_shadow(
		pos + Vector2(0, 9.0 * ui_scale),
		13.0 * ui_scale,
		0.2
	)

	draw_rect(
		Rect2(
			pos.x - 12.0 * ui_scale,
			pos.y - 8.0 * ui_scale,
			24.0 * ui_scale,
			18.0 * ui_scale
		),
		Color(0.95, 0.95, 0.95)
	)

	draw_circle(
		pos + Vector2(-4.0 * ui_scale, 1.0 * ui_scale),
		3.5 * ui_scale,
		Color(0.15, 0.15, 0.17)
	)

	draw_circle(
		pos + Vector2(6.0 * ui_scale, -3.0 * ui_scale),
		3.0 * ui_scale,
		Color(0.15, 0.15, 0.17)
	)

	draw_circle(
		pos + Vector2(-6.0 * ui_scale, -2.0 * ui_scale),
		3.0 * ui_scale,
		Color(0.1, 0.1, 0.1)
	)

	draw_circle(
		pos + Vector2(5.0 * ui_scale, 4.0 * ui_scale),
		3.0 * ui_scale,
		Color(0.1, 0.1, 0.1)
	)

	draw_circle(
		pos + Vector2(0, -10.0 * ui_scale),
		7.0 * ui_scale,
		Color(0.95, 0.95, 0.95)
	)

func draw_godot_character(pos: Vector2, is_dead: bool) -> void:
	draw_shadow(
		pos + Vector2(0, 26.0 * ui_scale),
		20.0 * ui_scale,
		0.22
	)

	if shield_active and state == GameState.PLAYING:
		draw_circle(
			pos,
			30.0 * ui_scale,
			Color(0.4, 0.8, 1, 0.25)
		)

		draw_arc(
			pos,
			30.0 * ui_scale,
			0,
			TAU,
			24,
			Color(0.4, 0.8, 1, 0.8),
			2.0 * ui_scale
		)

	if player_texture:
		var tex_size := player_texture.get_size()
		var target_size := Vector2(48, 48) * ui_scale
		var scale_factor: float = min(
			target_size.x / tex_size.x,
			target_size.y / tex_size.y
		)

		var draw_size := tex_size * scale_factor
		var rect := Rect2(pos - draw_size / 2.0, draw_size)
		var tint := Color(1, 0.55, 0.55) if is_dead else Color(1, 1, 1)

		draw_texture_rect(
			player_texture,
			rect,
			false,
			tint
		)

		return

	draw_godot_character_fallback(pos, is_dead)

func draw_godot_character_fallback(pos: Vector2, is_dead: bool) -> void:
	var body_col := Color(0.28, 0.55, 0.75) if is_dead else Color(0.28, 0.55, 0.75, 1.0)
	var size := 22.0 * ui_scale

	draw_rect(
		Rect2(
			pos.x - size * 0.75,
			pos.y - size * 1.15,
			size * 0.22,
			size * 0.4
		),
		body_col
	)

	draw_rect(
		Rect2(
			pos.x + size * 0.53,
			pos.y - size * 1.15,
			size * 0.22,
			size * 0.4
		),
		body_col
	)

	draw_circle(
		pos + Vector2(0, -size * 0.2),
		size * 0.95,
		body_col
	)

	draw_rect(
		Rect2(
			pos.x - size * 0.95,
			pos.y - size * 0.2,
			size * 1.9,
			size * 1.0
		),
		body_col
	)

	draw_circle(
		pos + Vector2(0, size * 0.8),
		size * 0.95,
		body_col
	)

	var eye_col := Color(0.4, 0.1, 0.1) if is_dead else Color(1, 1, 1)
	var pupil_col := Color(0.2, 0, 0) if is_dead else Color(0.1, 0.1, 0.15)

	draw_circle(
		pos + Vector2(-size * 0.42, -size * 0.05),
		size * 0.32,
		eye_col
	)

	draw_circle(
		pos + Vector2(size * 0.42, -size * 0.05),
		size * 0.32,
		eye_col
	)

	if not is_dead:
		draw_circle(
			pos + Vector2(-size * 0.42, -size * 0.02),
			size * 0.14,
			pupil_col
		)

		draw_circle(
			pos + Vector2(size * 0.42, -size * 0.02),
			size * 0.14,
			pupil_col
		)
	else:
		var o := size * 0.14

		draw_line(
			pos + Vector2(-size * 0.42 - o, -size * 0.05 - o),
			pos + Vector2(-size * 0.42 + o, -size * 0.05 + o),
			pupil_col,
			2.0 * ui_scale
		)

		draw_line(
			pos + Vector2(-size * 0.42 - o, -size * 0.05 + o),
			pos + Vector2(-size * 0.42 + o, -size * 0.05 - o),
			pupil_col,
			2.0 * ui_scale
		)

		draw_line(
			pos + Vector2(size * 0.42 - o, -size * 0.05 - o),
			pos + Vector2(size * 0.42 + o, -size * 0.05 + o),
			pupil_col,
			2.0 * ui_scale
		)

		draw_line(
			pos + Vector2(size * 0.42 - o, -size * 0.05 + o),
			pos + Vector2(size * 0.42 + o, -size * 0.05 - o),
			pupil_col,
			2.0 * ui_scale
		)

func draw_sad_face(pos: Vector2) -> void:
	draw_shadow(
		pos + Vector2(0, 35.0 * ui_scale),
		24.0 * ui_scale,
		0.2
	)

	draw_circle(
		pos,
		30.0 * ui_scale,
		Color(0.95, 0.8, 0.2)
	)

	draw_circle(
		pos + Vector2(-10.0 * ui_scale, -8.0 * ui_scale),
		4.0 * ui_scale,
		Color(0, 0, 0)
	)

	draw_circle(
		pos + Vector2(10.0 * ui_scale, -8.0 * ui_scale),
		4.0 * ui_scale,
		Color(0, 0, 0)
	)

	draw_arc(
		pos + Vector2(0, 18.0 * ui_scale),
		12.0 * ui_scale,
		PI + 0.3,
		TAU - 0.3,
		12,
		Color(0, 0, 0),
		2.0 * ui_scale
	)

func draw_discord_icon(rect: Rect2) -> void:
	var center := rect.position + rect.size / 2.0
	var radius := rect.size.x / 2.0
	var blurple := Color(0.345, 0.396, 0.949)
	var eye_r := radius * 0.22
	var eye_off := radius * 0.38

	draw_circle(center, radius, blurple)

	draw_circle(
		center + Vector2(-eye_off, -radius * 0.05),
		eye_r,
		Color(1, 1, 1)
	)

	draw_circle(
		center + Vector2(eye_off, -radius * 0.05),
		eye_r,
		Color(1, 1, 1)
	)

	draw_circle(
		center + Vector2(-radius * 0.95, -radius * 0.35),
		radius * 0.28,
		blurple
	)

	draw_circle(
		center + Vector2(radius * 0.95, -radius * 0.35),
		radius * 0.28,
		blurple
	)
