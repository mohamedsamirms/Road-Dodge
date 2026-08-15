extends Node2D

# ---------- Screen / road geometry ----------
const SCREEN_W := 400.0
const SCREEN_H := 700.0
const ROAD_LEFT := 100.0
const ROAD_RIGHT := 300.0
const LANE_COUNT := 3
const LANE_WIDTH := (ROAD_RIGHT - ROAD_LEFT) / LANE_COUNT

# ---------- Player ----------
const PLAYER_Y := 580.0
const LANE_MOVE_SPEED := 12.0
var player_lane := 1
var player_x := 0.0

# ---------- Run state ----------
var score := 0.0
var scroll_offset := 0.0
const SCROLL_SPEED := 220.0
var shield_active := false

# ---------- Obstacles / collectibles ----------
var entities := []      # Array of Dictionary {id, y, lane, type}
var next_id := 0
var spawn_timer := 0.0
var spawn_interval := 0.9

# ---------- Decoration ----------
var trees := []          # Array of Dictionary {y, side}

# ---------- Player texture ----------
const ICON_PATH := "res://icon.svg"
var player_texture: Texture2D = null

# ---------- Persistent save data ----------
const SAVE_PATH := "user://savegame.json"
var high_score := 0
var coins := 0                 # spendable currency, persists across runs
var upg_shield := 0            # 0 or 1
var upg_multiplier := 0        # 0..MULT_MAX
var upg_headstart := 0         # 0..HEADSTART_MAX

const MULT_STEP := 0.1
const MULT_MAX := 5
const HEADSTART_STEP := 0.2
const HEADSTART_MAX := 3
const SHIELD_COST := 40
const MULT_BASE_COST := 20
const HEADSTART_BASE_COST := 15

func score_multiplier() -> float:
	return 1.0 + upg_multiplier * MULT_STEP

func shield_cost() -> int:
	return SHIELD_COST

func mult_cost() -> int:
	return MULT_BASE_COST * (upg_multiplier + 1)

func headstart_cost() -> int:
	return HEADSTART_BASE_COST * (upg_headstart + 1)

# ---------- Game state machine ----------
enum GameState { LOADING, MENU, SHOP, PLAYING, GAME_OVER }
var state := GameState.LOADING
var loading_timer := 0.0
const LOADING_DURATION := 1.3

# ---------- Audio ----------
var sfx_coin: AudioStreamPlayer
var sfx_crash: AudioStreamPlayer
var sfx_switch: AudioStreamPlayer
var sfx_upgrade: AudioStreamPlayer
var sfx_shield: AudioStreamPlayer

func _ready() -> void:
	randomize()
	player_x = lane_center(player_lane)
	for i in range(6):
		trees.append({"y": i * 140.0 - 100.0, "side": i % 2})
	load_game()
	if ResourceLoader.exists(ICON_PATH):
		player_texture = load(ICON_PATH)
	sfx_coin = make_player("res://sfx/coin.wav")
	sfx_crash = make_player("res://sfx/crash.wav")
	sfx_switch = make_player("res://sfx/switch.wav")
	sfx_upgrade = make_player("res://sfx/upgrade.wav")
	sfx_shield = make_player("res://sfx/shield.wav")

func make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p

func play_sfx(p: AudioStreamPlayer) -> void:
	if p and p.stream:
		p.play()

# ---------- Save / load ----------
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		high_score = int(parsed.get("high_score", 0))
		coins = int(parsed.get("coins", 0))
		upg_shield = int(parsed.get("upg_shield", 0))
		upg_multiplier = int(parsed.get("upg_multiplier", 0))
		upg_headstart = int(parsed.get("upg_headstart", 0))
	else:
		# legacy save from an earlier version of this game (plain integer high score)
		high_score = text.strip_edges().to_int()

func save_game() -> void:
	var data := {
		"high_score": high_score,
		"coins": coins,
		"upg_shield": upg_shield,
		"upg_multiplier": upg_multiplier,
		"upg_headstart": upg_headstart,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func lane_center(lane: int) -> float:
	return ROAD_LEFT + LANE_WIDTH * (lane + 0.5)

# ---------- Upgrades ----------
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

# ---------- Input ----------
func _unhandled_input(event: InputEvent) -> void:
	var key_pressed = (event is InputEventKey) and event.pressed
	var tap_pos = null
	if event is InputEventScreenTouch and event.pressed:
		tap_pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap_pos = event.position

	match state:
		GameState.MENU:
			if key_pressed:
				if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
					start_run()
				elif event.keycode == KEY_S:
					state = GameState.SHOP
			elif tap_pos != null:
				if discord_icon_rect().has_point(tap_pos):
					open_discord()
				elif menu_shop_rect().has_point(tap_pos):
					state = GameState.SHOP
				elif menu_play_rect().has_point(tap_pos):
					start_run()
		GameState.SHOP:
			if key_pressed:
				if event.keycode == KEY_1:
					buy_shield()
				elif event.keycode == KEY_2:
					buy_multiplier()
				elif event.keycode == KEY_3:
					buy_headstart()
				elif event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE:
					state = GameState.MENU
			elif tap_pos != null:
				if discord_icon_rect().has_point(tap_pos):
					open_discord()
				elif shop_row_rect(0).has_point(tap_pos):
					buy_shield()
				elif shop_row_rect(1).has_point(tap_pos):
					buy_multiplier()
				elif shop_row_rect(2).has_point(tap_pos):
					buy_headstart()
				elif shop_back_rect().has_point(tap_pos):
					state = GameState.MENU
		GameState.PLAYING:
			if key_pressed:
				if (event.keycode == KEY_LEFT or event.keycode == KEY_A) and player_lane > 0:
					player_lane -= 1
					play_sfx(sfx_switch)
				elif (event.keycode == KEY_RIGHT or event.keycode == KEY_D) and player_lane < LANE_COUNT - 1:
					player_lane += 1
					play_sfx(sfx_switch)
			elif tap_pos != null:
				if tap_pos.x < SCREEN_W / 2.0 and player_lane > 0:
					player_lane -= 1
					play_sfx(sfx_switch)
				elif tap_pos.x >= SCREEN_W / 2.0 and player_lane < LANE_COUNT - 1:
					player_lane += 1
					play_sfx(sfx_switch)
		GameState.GAME_OVER:
			if tap_pos != null and discord_icon_rect().has_point(tap_pos):
				open_discord()
			elif key_pressed or tap_pos != null:
				state = GameState.MENU

# ---------- Discord link ----------
const DISCORD_URL := "https://discord.gg/xVbqpgH2GX"

func open_discord() -> void:
	OS.shell_open(DISCORD_URL)

func discord_icon_rect() -> Rect2:
	return Rect2(SCREEN_W - 46, 12, 32, 32)

# ---------- Shared UI hit-rects (used by both drawing and touch/click input) ----------
func menu_play_rect() -> Rect2:
	return Rect2(SCREEN_W / 2.0 - 90, SCREEN_H / 2.0 + 30, 180, 42)

func menu_shop_rect() -> Rect2:
	return Rect2(SCREEN_W / 2.0 - 90, SCREEN_H / 2.0 + 82, 180, 42)

func shop_row_rect(index: int) -> Rect2:
	return Rect2(16, 152 + index * 90, SCREEN_W - 32, 68)

func shop_back_rect() -> Rect2:
	return Rect2(SCREEN_W / 2.0 - 70, SCREEN_H - 62, 140, 40)

func start_run() -> void:
	score = 0.0
	shield_active = upg_shield >= 1
	entities.clear()
	player_lane = 1
	player_x = lane_center(player_lane)
	spawn_timer = 0.0
	spawn_interval = 0.9 + upg_headstart * HEADSTART_STEP
	state = GameState.PLAYING

# ---------- Update ----------
func _process(delta: float) -> void:
	match state:
		GameState.LOADING:
			loading_timer += delta
			if loading_timer >= LOADING_DURATION:
				state = GameState.MENU
		GameState.PLAYING:
			_process_gameplay(delta)
		_:
			pass
	queue_redraw()

func _process_gameplay(delta: float) -> void:
	score += delta * 10.0 * score_multiplier()
	scroll_offset = fmod(scroll_offset + SCROLL_SPEED * delta, 40.0)

	var target_x = lane_center(player_lane)
	player_x = lerp(player_x, target_x, delta * LANE_MOVE_SPEED)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval
		spawn_interval = max(0.45, spawn_interval - 0.01)
		var lane = randi() % LANE_COUNT
		var e_type = "car"
		var roll = randf()
		if roll < 0.25:
			e_type = "coin"
		elif roll < 0.4:
			e_type = "cow"
		entities.append({"id": next_id, "y": -40.0, "lane": lane, "type": e_type})
		next_id += 1

	var to_remove_ids := []
	for e in entities:
		e.y += SCROLL_SPEED * delta
		if abs(e.y - PLAYER_Y) < 18.0 and e.lane == player_lane:
			if e.type == "coin":
				score += 50 * score_multiplier()
				coins += 1
				to_remove_ids.append(e.id)
				play_sfx(sfx_coin)
			else:
				if shield_active:
					shield_active = false
					to_remove_ids.append(e.id)
					play_sfx(sfx_shield)
				else:
					end_run()
		if e.y > SCREEN_H + 40.0:
			to_remove_ids.append(e.id)
	if to_remove_ids.size() > 0:
		entities = entities.filter(func(e): return not to_remove_ids.has(e.id))

	for t in trees:
		t.y += SCROLL_SPEED * delta
		if t.y > SCREEN_H + 60.0:
			t.y -= 6 * 140.0

func end_run() -> void:
	state = GameState.GAME_OVER
	play_sfx(sfx_crash)
	if int(score) > high_score:
		high_score = int(score)
	save_game()

# ---------- Drawing ----------
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

func draw_road_background() -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0.87, 0.68, 0.47))
	draw_rect(Rect2(ROAD_LEFT, 0, ROAD_RIGHT - ROAD_LEFT, SCREEN_H), Color(0.2, 0.2, 0.22))
	draw_rect(Rect2(ROAD_LEFT - 4, 0, 4, SCREEN_H), Color(0.95, 0.8, 0.1))
	draw_rect(Rect2(ROAD_RIGHT, 0, 4, SCREEN_H), Color(0.95, 0.8, 0.1))

	var dash_len := 50.0
	var gap := 26.0
	var dash_width := 10.0
	var y := -scroll_offset
	var center_x = ROAD_LEFT + (ROAD_RIGHT - ROAD_LEFT) / 2.0
	while y < SCREEN_H:
		draw_rect(Rect2(center_x - dash_width / 2.0, y, dash_width, dash_len), Color(1, 1, 1, 0.9))
		y += dash_len + gap

	for t in trees:
		var tx = 40.0 if t.side == 0 else SCREEN_W - 40.0
		draw_tree(Vector2(tx, t.y))

func draw_entities() -> void:
	for e in entities:
		var ex = lane_center(e.lane)
		if e.type == "car":
			draw_car(Vector2(ex, e.y))
		elif e.type == "coin":
			draw_coin(Vector2(ex, e.y))
		elif e.type == "cow":
			draw_cow(Vector2(ex, e.y))

func draw_hud(font: Font) -> void:
	draw_string(font, Vector2(10, 30), "Score: %d" % int(score), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
	draw_string(font, Vector2(10, 54), "Best: %d" % high_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.2))
	draw_string(font, Vector2(10, 76), "Coins: %d" % coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.9, 1))
	if shield_active:
		draw_string(font, Vector2(SCREEN_W - 90, 30), "SHIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.8, 1))
	if state == GameState.PLAYING:
		draw_string(font, Vector2(10, SCREEN_H - 15), "<- A/D or Left/Right ->", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))

func draw_loading_screen(font: Font) -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0.13, 0.14, 0.17))
	draw_godot_character(Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0 - 60), false)
	draw_string(font, Vector2(SCREEN_W / 2.0 - 62, SCREEN_H / 2.0 + 10), "ROAD DODGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1))
	var bar_w := 220.0
	var bar_h := 14.0
	var bar_x := SCREEN_W / 2.0 - bar_w / 2.0
	var bar_y := SCREEN_H / 2.0 + 50.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.3, 0.3, 0.34))
	var pct = clamp(loading_timer / LOADING_DURATION, 0.0, 1.0)
	draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), Color(0.28, 0.55, 0.75))
	draw_string(font, Vector2(SCREEN_W / 2.0 - 32, bar_y + 34), "Loading...", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.85))

func draw_menu_screen(font: Font) -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.5))
	draw_godot_character(Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0 - 130), false)
	draw_string(font, Vector2(SCREEN_W / 2.0 - 62, SCREEN_H / 2.0 - 50), "ROAD DODGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1))
	draw_string(font, Vector2(SCREEN_W / 2.0 - 65, SCREEN_H / 2.0 - 15), "Best: %d   Coins: %d" % [high_score, coins], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.85, 0.2))

	var play_rect = menu_play_rect()
	draw_rect(play_rect, Color(0.28, 0.55, 0.75))
	draw_string(font, Vector2(play_rect.position.x + play_rect.size.x / 2.0 - 24, play_rect.position.y + 27), "PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))

	var shop_rect = menu_shop_rect()
	draw_rect(shop_rect, Color(0.3, 0.3, 0.34))
	draw_string(font, Vector2(shop_rect.position.x + shop_rect.size.x / 2.0 - 40, shop_rect.position.y + 27), "UPGRADES", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))

	draw_string(font, Vector2(SCREEN_W / 2.0 - 100, SCREEN_H / 2.0 + 150), "Tap, or SPACE / S on keyboard", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))
	draw_discord_icon(discord_icon_rect())

func draw_shop_screen(font: Font) -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.65))
	draw_string(font, Vector2(SCREEN_W / 2.0 - 45, 90), "UPGRADES", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1))
	draw_string(font, Vector2(SCREEN_W / 2.0 - 45, 118), "Coins: %d" % coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.9, 1))

	# Shield row
	var r0 = shop_row_rect(0)
	draw_rect(r0, Color(0.18, 0.18, 0.22))
	var shield_status = "OWNED" if upg_shield >= 1 else "Cost: %d" % shield_cost()
	var shield_col = Color(0.4, 1, 0.5) if upg_shield >= 1 else Color(1, 0.85, 0.4)
	draw_string(font, Vector2(r0.position.x + 8, r0.position.y + 26), "[1] Shield - absorb one hit per run", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))
	draw_string(font, Vector2(r0.position.x + 8, r0.position.y + 50), shield_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, shield_col)

	# Multiplier row
	var r1 = shop_row_rect(1)
	draw_rect(r1, Color(0.18, 0.18, 0.22))
	var mult_status = "MAX LEVEL" if upg_multiplier >= MULT_MAX else "Cost: %d" % mult_cost()
	draw_string(font, Vector2(r1.position.x + 8, r1.position.y + 26), "[2] Score Boost - Lv %d/%d (+%d%%)" % [upg_multiplier, MULT_MAX, int(upg_multiplier * MULT_STEP * 100)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))
	draw_string(font, Vector2(r1.position.x + 8, r1.position.y + 50), mult_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.4))

	# Head start row
	var r2 = shop_row_rect(2)
	draw_rect(r2, Color(0.18, 0.18, 0.22))
	var hs_status = "MAX LEVEL" if upg_headstart >= HEADSTART_MAX else "Cost: %d" % headstart_cost()
	draw_string(font, Vector2(r2.position.x + 8, r2.position.y + 26), "[3] Head Start - Lv %d/%d (easier start)" % [upg_headstart, HEADSTART_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))
	draw_string(font, Vector2(r2.position.x + 8, r2.position.y + 50), hs_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.9, 1))

	var back_rect = shop_back_rect()
	draw_rect(back_rect, Color(0.3, 0.3, 0.34))
	draw_string(font, Vector2(back_rect.position.x + back_rect.size.x / 2.0 - 24, back_rect.position.y + 25), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
	draw_discord_icon(discord_icon_rect())

func draw_gameover_screen(font: Font) -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.55))
	draw_sad_face(Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0 - 70))
	draw_string(font, Vector2(SCREEN_W / 2.0 - 60, SCREEN_H / 2.0 + 10), "GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1))
	draw_string(font, Vector2(SCREEN_W / 2.0 - 55, SCREEN_H / 2.0 + 45), "Score: %d" % int(score), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
	var best_col = Color(1, 0.85, 0.2) if int(score) < high_score else Color(0.3, 1, 0.4)
	var best_label = "Best: %d" % high_score if int(score) < high_score else "NEW BEST: %d" % high_score
	draw_string(font, Vector2(SCREEN_W / 2.0 - 55, SCREEN_H / 2.0 + 72), best_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, best_col)
	draw_string(font, Vector2(SCREEN_W / 2.0 - 95, SCREEN_H / 2.0 + 105), "Press any key to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.9))
	draw_discord_icon(discord_icon_rect())

func draw_tree(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x - 3, pos.y, 6, 20), Color(0.4, 0.25, 0.1))
	draw_circle(pos + Vector2(0, -10), 16, Color(0.2, 0.6, 0.25))

func draw_car(pos: Vector2) -> void:
	var w := 26.0
	var h := 40.0
	draw_rect(Rect2(pos.x - w / 2, pos.y - h / 2, w, h), Color(0.8, 0.15, 0.15))
	draw_rect(Rect2(pos.x - w / 2 + 3, pos.y - h / 2 + 6, w - 6, 10), Color(0.6, 0.85, 0.95))
	draw_circle(pos + Vector2(-w / 2, h / 2 - 4), 4, Color(0.05, 0.05, 0.05))
	draw_circle(pos + Vector2(w / 2, h / 2 - 4), 4, Color(0.05, 0.05, 0.05))
	draw_circle(pos + Vector2(-w / 2, -h / 2 + 4), 4, Color(0.05, 0.05, 0.05))
	draw_circle(pos + Vector2(w / 2, -h / 2 + 4), 4, Color(0.05, 0.05, 0.05))

func draw_coin(pos: Vector2) -> void:
	draw_circle(pos, 9, Color(0.95, 0.85, 0.2))
	draw_arc(pos, 9, 0, TAU, 16, Color(0.6, 0.5, 0.05), 2.0)

func draw_cow(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x - 12, pos.y - 8, 24, 18), Color(0.95, 0.95, 0.95))
	draw_circle(pos + Vector2(-6, -2), 3, Color(0.1, 0.1, 0.1))
	draw_circle(pos + Vector2(5, 4), 3, Color(0.1, 0.1, 0.1))
	draw_circle(pos + Vector2(0, -10), 7, Color(0.95, 0.95, 0.95))

func draw_godot_character(pos: Vector2, is_dead: bool) -> void:
	if shield_active and state == GameState.PLAYING:
		draw_circle(pos, 30, Color(0.4, 0.8, 1, 0.25))
		draw_arc(pos, 30, 0, TAU, 24, Color(0.4, 0.8, 1, 0.8), 2.0)
	if player_texture:
		var tex_size = player_texture.get_size()
		var target_size = Vector2(48, 48)
		var scale_factor = min(target_size.x / tex_size.x, target_size.y / tex_size.y)
		var draw_size = tex_size * scale_factor
		var rect = Rect2(pos - draw_size / 2.0, draw_size)
		var tint = Color(1, 0.55, 0.55) if is_dead else Color(1, 1, 1)
		draw_texture_rect(player_texture, rect, false, tint)
		return
	draw_godot_character_fallback(pos, is_dead)

func draw_godot_character_fallback(pos: Vector2, is_dead: bool) -> void:
	# Used only if res://icon.svg isn't found - a drawn approximation of
	# Godot's blue robot mascot so the game still looks right without it.
	var body_col = Color(0.28, 0.55, 0.75) if is_dead else Color(0.28, 0.55, 0.75, 1.0)
	var size = 22.0

	draw_rect(Rect2(pos.x - size * 0.75, pos.y - size * 1.15, size * 0.22, size * 0.4), body_col)
	draw_rect(Rect2(pos.x + size * 0.53, pos.y - size * 1.15, size * 0.22, size * 0.4), body_col)

	draw_circle(pos + Vector2(0, -size * 0.2), size * 0.95, body_col)
	draw_rect(Rect2(pos.x - size * 0.95, pos.y - size * 0.2, size * 1.9, size * 1.0), body_col)
	draw_circle(pos + Vector2(0, size * 0.8), size * 0.95, body_col)

	var eye_col = Color(0.4, 0.1, 0.1) if is_dead else Color(1, 1, 1)
	var pupil_col = Color(0.2, 0, 0) if is_dead else Color(0.1, 0.1, 0.15)
	draw_circle(pos + Vector2(-size * 0.42, -size * 0.05), size * 0.32, eye_col)
	draw_circle(pos + Vector2(size * 0.42, -size * 0.05), size * 0.32, eye_col)
	if not is_dead:
		draw_circle(pos + Vector2(-size * 0.42, -size * 0.02), size * 0.14, pupil_col)
		draw_circle(pos + Vector2(size * 0.42, -size * 0.02), size * 0.14, pupil_col)
	else:
		var o = size * 0.14
		draw_line(pos + Vector2(-size * 0.42 - o, -size * 0.05 - o), pos + Vector2(-size * 0.42 + o, -size * 0.05 + o), pupil_col, 2.0)
		draw_line(pos + Vector2(-size * 0.42 - o, -size * 0.05 + o), pos + Vector2(-size * 0.42 + o, -size * 0.05 - o), pupil_col, 2.0)
		draw_line(pos + Vector2(size * 0.42 - o, -size * 0.05 - o), pos + Vector2(size * 0.42 + o, -size * 0.05 + o), pupil_col, 2.0)
		draw_line(pos + Vector2(size * 0.42 - o, -size * 0.05 + o), pos + Vector2(size * 0.42 + o, -size * 0.05 - o), pupil_col, 2.0)

func draw_sad_face(pos: Vector2) -> void:
	draw_circle(pos, 30, Color(0.95, 0.8, 0.2))
	draw_circle(pos + Vector2(-10, -8), 4, Color(0, 0, 0))
	draw_circle(pos + Vector2(10, -8), 4, Color(0, 0, 0))
	draw_arc(pos + Vector2(0, 18), 12, PI + 0.3, TAU - 0.3, 12, Color(0, 0, 0), 2.0)

func draw_discord_icon(rect: Rect2) -> void:
	#dihcord icon
	var center = rect.position + rect.size / 2.0
	var radius = rect.size.x / 2.0
	var blurple = Color(0.345, 0.396, 0.949)
	draw_circle(center, radius, blurple)
	var eye_r = radius * 0.22
	var eye_off = radius * 0.38
	draw_circle(center + Vector2(-eye_off, -radius * 0.05), eye_r, Color(1, 1, 1))
	draw_circle(center + Vector2(eye_off, -radius * 0.05), eye_r, Color(1, 1, 1))

	draw_circle(center + Vector2(-radius * 0.95, -radius * 0.35), radius * 0.28, blurple)
	draw_circle(center + Vector2(radius * 0.95, -radius * 0.35), radius * 0.28, blurple)
