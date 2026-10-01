extends Control

const Game = preload("res://scripts/dungeon_game.gd")
const Content = preload("res://scripts/content_catalog.gd")
const Talents = preload("res://scripts/talent_catalog.gd")
const Lords = preload("res://scripts/lord_catalog.gd")
const LordProgression = preload("res://scripts/lord_progression.gd")
const DungeonView = preload("res://scripts/dungeon_view.gd")
const TutorialGuide = preload("res://scripts/tutorial_guide.gd")
const INK = Color("#0e1118")
const PANEL = Color("#181e28")
const TILE = Color("#212938")
const LINE = Color("#333e4e")
const PAPER = Color("#ede5d5")
const MUTED = Color("#929eaf")
const GOLD = Color("#dfba70")
const RED = Color("#d97e78")
const GREEN = Color("#83bfa6")
const VIOLET = Color("#ae97d4")

var game = Game.new()
var selected_slot: int = -1
var selected_room: String = ""
var selecting_deal: bool = false
var speed: int = 1
var paused: bool = false
var sound_on: bool = true
var accumulator: float = 0.0
var message: String = "Выберите комнату в магазине, затем свободное место на этаже."
var profile: Dictionary = {"wave": 0, "kills": 0, "floors": 1, "level": 1, "unlocked_paths": []}
var page: VBoxContainer
var floor_scroll: ScrollContainer
var log_box: RichTextLabel
var scroll_position: int = 0
var active_floor: int = -1
var modal: PanelContainer
var modal_shade: ColorRect
var audio_player: AudioStreamPlayer
var sounds: Dictionary = {}
var screenshot_path: String = ""
var demo_mode: bool = false
var preview_raid: bool = false
var menu_open: bool = true
var has_run: bool = false
var volume: float = 0.65
var dungeon_view: Control
var menu_preview: Control
var resume_paused: bool = false
var viewing_talents: bool = false
var lords_profile: Dictionary = LordProgression.default_profile()
var menu_section: String = "home"
var inspected_lord: String = "fallen_knight"
var lord_message: String = ""
var run_best_at_start: int = 0
var run_reward_claimed: bool = true
var last_run_reward: Dictionary = {}
var tutorial = TutorialGuide.new()
var tutorial_saved_speed: int = 1

func _ready() -> void:
	_load_local()
	game.unlocked_paths.assign(profile.get("unlocked_paths", []))
	game.restart()
	_configure_selected_lord(game)
	get_tree().auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			screenshot_path = argument.trim_prefix("--capture=")
		if argument == "--demo":
			demo_mode = true
		if argument == "--preview-raid":
			preview_raid = true
	if demo_mode:
		menu_open = false
		has_run = true
		_make_demo()
		if preview_raid:
			game.start_raid()
			for step_index in range(5):
				game.step()
			paused = true
	_make_theme()
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	for key in ["click", "hit", "win", "lose"]:
		sounds[key] = _make_sound(key)
	_build_shell()
	_refresh()
	if not screenshot_path.is_empty():
		_capture.call_deferred()

func _make_theme() -> void:
	var ui_theme = Theme.new()
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", PAPER)
	ui_theme.set_color("font_color", "Button", PAPER)
	ui_theme.set_color("font_disabled_color", "Button", Color("#606b7c"))
	ui_theme.set_color("font_hover_color", "Button", Color.WHITE)
	ui_theme.set_constant("outline_size", "Label", 0)
	ui_theme.set_constant("separation", "VBoxContainer", 8)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	ui_theme.set_stylebox("normal", "Button", _style(TILE, LINE, 8, 10))
	ui_theme.set_stylebox("hover", "Button", _style(Color("#303a49"), GOLD, 8, 10))
	ui_theme.set_stylebox("pressed", "Button", _style(Color("#393a36"), GOLD, 8, 10))
	ui_theme.set_stylebox("disabled", "Button", _style(Color("#181e27"), Color("#283140"), 8, 10))
	ui_theme.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, GOLD, 8, 2))
	ui_theme.set_stylebox("background", "ProgressBar", _style(Color("#10151d"), Color.TRANSPARENT, 4, 0))
	ui_theme.set_stylebox("fill", "ProgressBar", _style(GREEN, Color.TRANSPARENT, 4, 0))
	theme = ui_theme

func _build_shell() -> void:
	var bg = ColorRect.new()
	bg.color = INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

func _refresh() -> void:
	if tutorial.observe(game):
		paused = true
		accumulator = 0.0
	if is_instance_valid(floor_scroll):
		scroll_position = floor_scroll.scroll_vertical
	if is_instance_valid(dungeon_view) and dungeon_view.get_parent():
		dungeon_view.get_parent().remove_child(dungeon_view)
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	if menu_open:
		if menu_section == "lords":
			_build_lords_page()
		else:
			_build_menu()
		return
	_header()
	if tutorial.active():
		_tutorial_banner(page)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	page.add_child(body)
	_party_panel(body)
	_dungeon_panel(body)
	_inspector_panel(body)
	_shop_panel()
	_footer()
	floor_scroll.set_deferred("scroll_vertical", scroll_position)
	if game.phase == "raid":
		var target_floor: int = mini(game.current_slot / 5, game.floor_count)
		if target_floor != active_floor and game.current_slot >= 0:
			active_floor = target_floor
			floor_scroll.set_deferred("scroll_vertical", target_floor * 160)
	_show_phase_modal()

func _header() -> void:
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	page.add_child(head)
	var mark = _icon("res://assets/icons/lord.svg", 52)
	head.add_child(mark)
	var brand = VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	head.add_child(brand)
	brand.add_child(_label("ЛОРД ПОДЗЕМЕЛЬЯ", 25, PAPER))
	brand.add_child(_label("ПОСТРОЙ ИМПЕРИЮ. ПЕРЕЖИВИ СЛЕДУЮЩУЮ ВОЛНУ.", 10, MUTED))
	_stat(head, "ВОЛНА", str(game.wave), PAPER)
	_stat(head, "ЗОЛОТО", str(game.gold), GOLD)
	_stat(head, "РЕКОРД", str(int(profile.get("wave", 0))), VIOLET)
	var small = VBoxContainer.new()
	head.add_child(small)
	small.add_child(_button("Меню", _open_menu))
	small.add_child(_button("Звук: " + ("вкл" if sound_on else "выкл"), _toggle_sound))

func _party_panel(parent: Control) -> void:
	var box = _panel(parent, 222)
	var outer_scroll = ScrollContainer.new()
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(outer_scroll)
	var side = _vbox(outer_scroll)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_eyebrow("РАЗВЕДКА"))
	side.add_child(_label("Приключенцы", 23))
	var state_text: String = "Следующая группа" if game.phase == "prepare" else "Группа в подземелье"
	side.add_child(_label(state_text + " · %d чел." % game.heroes.size(), 12, MUTED))
	var expedition: String = game.wave_title
	var expedition_label = _label(expedition, 12, GOLD, true)
	expedition_label.tooltip_text = game.wave_description
	side.add_child(expedition_label)
	var party_scroll = ScrollContainer.new()
	party_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(party_scroll)
	var heroes_col = VBoxContainer.new()
	heroes_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_scroll.add_child(heroes_col)
	for hero in game.heroes:
		var card = PanelContainer.new()
		var compact: bool = game.heroes.size() > 1
		card.add_theme_stylebox_override("panel", _style(TILE if hero.hp > 0 else Color("#1d2027"), LINE, 8, 7 if compact else 10))
		heroes_col.add_child(card)
		var inner = _vbox(card, 3 if compact else 5)
		var row = HBoxContainer.new()
		inner.add_child(row)
		var definition: Dictionary = Content.hero(str(hero.id))
		var portrait = _icon(str(definition.get("icon", "")), 28 if compact else 36)
		portrait.modulate.a = 1.0 if hero.hp > 0 else 0.3
		row.add_child(portrait)
		var names = VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 1)
		row.add_child(names)
		names.add_child(_label(str(definition.get("name", hero.id)), 14 if compact else 16, PAPER if hero.hp > 0 else MUTED))
		names.add_child(_label("Ур. %d  ·  XP %d/%d" % [hero.level, hero.xp, 8 + 4 * (int(hero.level) - 1)], 11, VIOLET))
		inner.add_child(_bar(float(hero.hp), float(hero.max_hp), RED if hero.hp > 0 else MUTED))
		inner.add_child(_label("%d/%d HP    Урон %d  ·  Броня %d" % [maxi(0, hero.hp), hero.max_hp, hero.damage, hero.armor], 11, MUTED))
		var status: String = _hero_status(hero, definition)
		var items: Array = hero.get("items", [])
		if not items.is_empty():
			var names_list: PackedStringArray = []
			for id in items:
				names_list.append(str(Content.item(str(id)).get("name", id)))
			status += " · " + ", ".join(names_list)
		card.tooltip_text = str(definition.get("trait", "")) + "\n" + status
		var status_label = _label(status, 10 if compact else 11, GREEN if int(hero.get("poison_ticks", 0)) > 0 else MUTED, true)
		inner.add_child(status_label)
	if tutorial.active():
		_tutorial_context(side, "party")
	side.add_child(HSeparator.new())
	_lord_status(side)

func _lord_status(parent: Control) -> void:
	var identity: Dictionary = Lords.get_lord(game.lord_archetype)
	var row = HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_icon(str(identity.get("icon", "res://assets/icons/lord.svg")), 30))
	var name_label = _label(str(identity.get("name", "Лорд Подземелья")), 16, GOLD, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = str(identity.get("passive_description", ""))
	row.add_child(name_label)
	parent.add_child(_label("Уровень %d · мастерство %d / 5" % [game.lord.level, game.lord_mastery], 11, VIOLET))
	parent.add_child(_bar(float(game.lord.hp), float(game.lord.max_hp), GOLD))
	parent.add_child(_label("%d/%d HP · Урон %d · Броня %d" % [maxi(0, game.lord.hp), game.lord.max_hp, game.lord.damage, game.lord.armor], 11, MUTED, true))
	parent.add_child(_label("До таланта: XP %d / %d" % [game.lord.xp, 10 + 6 * (int(game.lord.level) - 1)], 11, VIOLET))
	parent.add_child(_button("Таланты Владыки · %d" % _talent_count(), _show_talents))

func _dungeon_panel(parent: Control) -> void:
	var box = _panel(parent)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center = _vbox(box, 8)
	var title_row = HBoxContainer.new()
	center.add_child(title_row)
	var title = _label("Глубины вашего подземелья", 21, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_label("%d этаж. / %d мест" % [game.floor_count, game.rooms.size()], 11, GOLD))
	_faction_counters(center)
	var guidance: String = message
	if selecting_deal and game.phase == "prepare":
		guidance = "Сделка: выберите пустое место. Отмена — Esc или «Снять выбор»."
	elif not selected_room.is_empty() and game.phase == "prepare":
		guidance = "Разместить: %s. Выберите пустую комнату." % Content.room(selected_room).name
	elif selected_slot >= 0 and game.phase == "prepare":
		guidance = "Выберите другой слот для переноса или обмена."
	elif game.phase == "raid":
		guidance = str(game.last_action.get("text", "Группа спускается в подземелье."))
		if guidance.is_empty():
			guidance = "Группа спускается в подземелье."
	var caption = _label(guidance, 12, GOLD if game.phase == "raid" else MUTED, true)
	caption.custom_minimum_size.y = 34
	center.add_child(caption)
	floor_scroll = ScrollContainer.new()
	floor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(floor_scroll)
	if not is_instance_valid(dungeon_view):
		dungeon_view = DungeonView.new()
		dungeon_view.slot_clicked.connect(_slot_clicked)
	dungeon_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_scroll.add_child(dungeon_view)
	var preview_room: String = str(game.deal_offer().get("room_id", "")) if selecting_deal else selected_room
	dungeon_view.configure(game, selected_slot, preview_room)
	dungeon_view.tutorial_slot = _tutorial_slot()
	var floor_button = _button("+ УГЛУБИТЬ ПОДЗЕМЕЛЬЕ · %d зол." % game.floor_cost(), _buy_floor, game.phase != "prepare" or game.gold < game.floor_cost())
	floor_button.custom_minimum_size.y = 38
	floor_button.tooltip_text = "Пять новых комнат и выбор свойства этажа: лаборатория, казармы или мастерская."
	center.add_child(floor_button)
	_tutorial_mark(floor_button, "floor")

func _inspector_panel(parent: Control) -> void:
	var box = _panel(parent, 242)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var right = _vbox(scroll)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_raid: bool = game.phase == "raid"
	right.add_child(_label("Ход рейда" if is_raid else "Комната" if selected_slot >= 0 else "Подземелье", 21))
	if is_raid:
		var defender_name: String = str(game.defender.get("name", "Герои входят…"))
		right.add_child(_label(defender_name, 17, GOLD, true))
		if not game.defender.is_empty() and int(game.defender.get("max_hp", 0)) > 0:
			right.add_child(_bar(float(game.defender.get("hp", 0)), float(game.defender.get("max_hp", 1)), RED))
			right.add_child(_label("HP %d · Урон %d" % [maxi(0, int(game.defender.get("hp", 0))), game.defender.get("damage", 0)], 12, MUTED, true))
			if game.rage > 0:
				right.add_child(_label("Ярость: +%d урона" % game.rage, 12, RED))
			if str(game.defender.get("id", "")) == "lord" and game.selected_talents.has("opening_wrath"):
				var strikes_left: int = maxi(0, 3 - int(game.lord_strikes))
				right.add_child(_label("Удары ×2: осталось %d / 3" % strikes_left, 12, VIOLET, true))
		elif not game.defender.is_empty():
			right.add_child(_label("Ловушка · эффект при входе", 12, MUTED, true))
		var ability_effect: String = str(game.ability_status().get("effect", ""))
		if not ability_effect.is_empty():
			right.add_child(_label(ability_effect, 12, GREEN, true))
		var controls = HBoxContainer.new()
		right.add_child(controls)
		controls.add_child(_button("▶" if paused else "Ⅱ", _toggle_pause))
		for value in [1, 2, 4]:
			var speed_btn = _button("×%d" % value, _set_speed.bind(value))
			if speed == value:
				speed_btn.add_theme_color_override("font_color", GOLD)
			controls.add_child(speed_btn)
		right.add_child(_label(game.wave_description, 12, MUTED, true))
	elif selected_slot >= 0 and selected_slot < game.rooms.size() and not game.rooms[selected_slot].is_empty():
		var stats: Dictionary = game.room_stats(selected_slot)
		right.add_child(_label(str(stats.name), 18, GOLD, true))
		var faction: Dictionary = Game.room_faction(str(stats.id))
		right.add_child(_label("%s · ранг %d" % [faction.get("name", ""), stats.get("rank", 1)], 12, faction.get("color", MUTED)))
		right.add_child(_label(Content.room_traits_text(stats), 11, MUTED, true))
		_disclosure(right, "Свойства и цели", str(stats.description) + "\n" + _matchup_text(stats))
		if str(stats.get("kind", "")) in ["shackles", "silence", "rust"]:
			right.add_child(_label("Контроль %d т. · удар %d\nБез XP героям" % [int(stats.get("effect_turns", 0)), int(stats.get("impact_damage", 0))], 12, PAPER, true))
			if bool(stats.get("impact_all", false)):
				right.add_child(_label("Удар по группе · 60% каждому", 12, VIOLET, true))
		elif str(stats.get("kind", "")) != "monster":
			right.add_child(_label("Урон %d · без XP героям" % int(stats.get("damage", 0)), 12, PAPER, true))
			if str(stats.id) in ["ballista", "blade_floor"]:
				right.add_child(_label(str(stats.get("role", "")), 12, VIOLET, true))
		else:
			right.add_child(_label("HP %d  ·  Урон %d\nБроня %d  ·  XP врагу %d" % [stats.get("hp", 0), stats.get("damage", 0), stats.get("armor", 0), stats.get("xp", 0)], 12, PAPER, true))
		_room_combo_details(right, selected_slot)
		_room_progression_details(right, selected_slot)
		var rank_limit: int = int(stats.get("max_rank", 0))
		var rank_capped: bool = rank_limit > 0 and int(stats.get("rank", 1)) >= rank_limit
		var upgrade_button = _button("Максимальный ранг · %d" % rank_limit if rank_capped else "Улучшить · %d зол." % game.upgrade_cost(selected_slot), _upgrade, rank_capped or game.phase != "prepare" or game.gold < game.upgrade_cost(selected_slot))
		right.add_child(upgrade_button)
		_tutorial_mark(upgrade_button, "upgrade")
		if not game.room_evolution_options(selected_slot).is_empty():
			var evolution_options: Array = game.room_evolution_options(selected_slot)
			var evolution_button = _button("Выбрать ветку · ранг %d →" % int(evolution_options[0].get("tier", 1)), _show_specializations.bind(selected_slot), game.phase != "prepare")
			evolution_button.add_theme_color_override("font_color", GOLD)
			right.add_child(evolution_button)
			_tutorial_mark(evolution_button, "evolution")
		right.add_child(_button("Продать · +%d зол." % game.sell_value(selected_slot), _sell, game.phase != "prepare"))
		right.add_child(_button("Отменить выбор", _cancel_selection))
	else:
		if tutorial.active():
			_tutorial_context(right, "planning")
		right.add_child(_button("Лечить Лорда · %d зол." % game.heal_cost(), _heal, game.phase != "prepare" or game.gold < game.heal_cost() or game.lord.hp >= game.lord.max_hp))
		var modifiers: Dictionary = game.talent_modifiers()
		var passive: Dictionary = game.lord_passive_modifiers()
		right.add_child(_label("Существа: HP %s · урон %s\nЛовушки: урон %s" % [_percent(float(modifiers.get("monster_hp", 0.0)) + float(passive.get("monster_hp", 0.0))), _percent(float(modifiers.get("monster_damage", 0.0))), _percent(float(modifiers.get("trap_damage", 0.0)))], 11, VIOLET, true))
	right.add_child(_button("Комбо · %d  /  Реликвии · %d" % [game.active_combos().size(), game.selected_relics.size()], _show_run_collection))
	if not game.battle_room_report().is_empty():
		right.add_child(_button("Вклад комнат · " + ("текущий бой" if is_raid else "прошлый бой"), _show_battle_report))
	right.add_child(HSeparator.new())
	right.add_child(_eyebrow("ЛЕТОПИСЬ"))
	log_box = RichTextLabel.new()
	log_box.custom_minimum_size.y = 130
	log_box.bbcode_enabled = false
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 11)
	log_box.add_theme_color_override("default_color", MUTED)
	right.add_child(log_box)
	for line in game.logs:
		log_box.append_text(str(line) + "\n\n")

func _shop_panel() -> void:
	var shop_area = VBoxContainer.new()
	shop_area.add_theme_constant_override("separation", 7)
	page.add_child(shop_area)
	var header = HBoxContainer.new()
	shop_area.add_child(header)
	var title = _eyebrow("МАГАЗИН КОМНАТ")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var offer: Dictionary = game.deal_offer()
	if not offer.is_empty():
		_deal_card(header, offer)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	shop_area.add_child(row)
	for id in game.shop:
		var definition: Dictionary = Content.room(str(id))
		var faction: Dictionary = Game.room_faction(str(id))
		var faction_color: Color = faction.get("color", MUTED)
		var stock: int = int(game.shop[id])
		var reward_xp: int = game.hero_room_xp(int(definition.xp))
		var button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 98
		button.disabled = game.phase != "prepare" or stock <= 0 or game.gold < int(definition.cost)
		button.tooltip_text = "%s\nБазовые HP: %d · Урон: %d · Броня: %d\nНаграда врагу на ранге 1: %d XP" % [definition.description, definition.hp, definition.damage, definition.armor, reward_xp]
		if str(definition.kind) in ["shackles", "silence", "rust"]:
			button.tooltip_text = "%s\nБазовая длительность: %d т. · срабатывает в следующем бою.\nНе даёт героям XP." % [definition.description, definition.get("effect_turns", 0)]
		elif str(definition.kind) != "monster":
			button.tooltip_text = "%s\nУрон: %d · без XP героям\n%s" % [definition.description, int(definition.damage), str(definition.get("role", ""))]
		button.tooltip_text = Content.room_traits_text(definition) + "\n" + button.tooltip_text
		button.pressed.connect(_select_shop.bind(str(id)))
		_style_faction_card(button, faction_color, selected_room == str(id))
		row.add_child(button)
		var margin = MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 10)
		button.add_child(margin)
		var contents = HBoxContainer.new()
		margin.add_child(contents)
		contents.add_child(_icon(str(definition.icon), 45))
		var text_col = VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.add_theme_constant_override("separation", 4)
		contents.add_child(text_col)
		var room_name = _label(("✓ " if selected_room == str(id) else "") + str(definition.name), 14, PAPER if not button.disabled else MUTED)
		room_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_col.add_child(room_name)
		text_col.add_child(_label("%d зол.   ·   запас %d" % [definition.cost, stock], 12, GOLD))
		text_col.add_child(_label(str(faction.get("name", "")), 10, faction_color))
		var detail: String = "Врагу: %d XP%s" % [reward_xp, " + предмет" if not str(definition.item).is_empty() else ""] if str(definition.kind) == "monster" else "Ловушка · без XP врагу"
		if str(definition.kind) in ["shackles", "silence", "rust"]:
			detail = "Контроль · %d боевых т." % int(definition.get("effect_turns", 0))
		text_col.add_child(_label(detail, 10, MUTED))
		_ignore_mouse(margin)
		_tutorial_mark(button, "shop:" + str(id))
		# Tutorial focus retains faction identity; selection uses a check and fill.
		if tutorial.active() and tutorial.target() == "shop:" + str(id) and not button.disabled:
			_style_faction_card(button, faction_color, true)

func _footer() -> void:
	var row = HBoxContainer.new()
	page.add_child(row)
	var desc = _label("Подготовка · продумайте порядок комнат" if game.phase == "prepare" else "Защита действует автоматически", 13, MUTED, true)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)
	if game.phase == "prepare":
		if selected_slot >= 0 or not selected_room.is_empty() or selecting_deal:
			row.add_child(_button("Снять выбор", _cancel_selection))
		var start = _button("НАЧАТЬ ВОЛНУ %d   →" % game.wave, _start)
		start.custom_minimum_size = Vector2(255, 42)
		start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 8, 12))
		start.add_theme_color_override("font_color", INK)
		start.add_theme_color_override("font_hover_color", GOLD)
		row.add_child(start)
		_tutorial_mark(start, "start")
	elif game.phase == "raid":
		var ability: Dictionary = game.ability_status()
		desc.text = "Пробел — пауза · Q — сила Лорда" if bool(ability.can_cast) else str(ability.reason)
		var cast = _button("Q · %s · %d/%d" % [ability.name, ability.charges, ability.max_charges], _cast_lord_ability, not bool(ability.can_cast))
		cast.custom_minimum_size = Vector2(300, 42)
		cast.tooltip_text = str(ability.description) + "\n" + str(ability.reason)
		cast.add_theme_color_override("font_color", GREEN)
		row.add_child(cast)
		_tutorial_mark(cast, "ability")
		row.add_child(_label(("ПАУЗА" if paused else "РЕЙД ИДЁТ") + "   ×%d" % speed, 17, GOLD))
	else:
		row.add_child(_button("Показать результат", _show_phase_modal))

func _process(delta: float) -> void:
	if menu_open or game.phase != "raid" or paused or is_instance_valid(modal):
		return
	accumulator += delta * speed
	if accumulator >= 0.5:
		accumulator -= 0.5
		game.step()
		_sound("hit" if game.phase == "raid" else ("lose" if game.phase == "defeat" else "win"))
		if game.phase != "raid":
			_update_record()
		_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Q or event.physical_keycode == KEY_Q:
			_cast_lord_ability()
		if event.keycode == KEY_SPACE and not menu_open and game.phase == "raid" and not is_instance_valid(modal):
			_toggle_pause()
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(modal):
				if viewing_talents:
					_back_from_talents()
				elif game.phase in ["prepare", "raid"] or menu_open:
					_close_modal()
			elif tutorial.active() and not menu_open:
				_open_menu()
			elif menu_open:
				if menu_section == "lords":
					_leave_lords()
				else:
					_resume_run()
			elif selected_slot >= 0 or not selected_room.is_empty() or selecting_deal:
				_cancel_selection()
			else:
				_open_menu()

func _toggle_fullscreen() -> void:
	var window: Window = get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN

func _slot_clicked(index: int) -> void:
	if menu_open or is_instance_valid(modal) or game.phase != "prepare" or not _tutorial_allow("slot:" + str(index)):
		return
	if selecting_deal:
		var error: String = game.buy_deal_room(index)
		if error.is_empty():
			selecting_deal = false
			selected_slot = index
		_action(error)
	elif not selected_room.is_empty():
		var error: String = game.buy_room(index, selected_room)
		if error.is_empty():
			tutorial.accepted("slot:" + str(index))
			if tutorial.active():
				selected_room = ""
		_action(error)
		if int(game.shop.get(selected_room, 0)) <= 0:
			selected_room = ""
		_refresh()
		if error.is_empty() and not tutorial.active() and not game.room_evolution_options(index).is_empty():
			selected_room = ""
			selected_slot = index
			_refresh()
	elif selected_slot >= 0:
		if selected_slot == index:
			_cancel_selection()
		else:
			_action(game.move_room(selected_slot, index))
			selected_slot = -1
			_refresh()
	elif not game.rooms[index].is_empty():
		selected_slot = index
		tutorial.accepted("slot:" + str(index))
		_refresh()
	else:
		message = "Сначала выберите тип комнаты в магазине внизу."
		_refresh()

func _select_shop(id: String) -> void:
	if not _tutorial_allow("shop:" + id):
		return
	selected_slot = -1
	selecting_deal = false
	selected_room = id if tutorial.active() else ("" if selected_room == id else id)
	tutorial.accepted("shop:" + id)
	_sound("click")
	_refresh()

func _cancel_selection() -> void:
	if not _tutorial_allow("cancel"):
		return
	selected_slot = -1
	selected_room = ""
	selecting_deal = false
	message = "Выберите комнату в магазине или улучшите построенную."
	_refresh()

func _upgrade() -> void:
	if not _tutorial_allow("upgrade"):
		return
	var error: String = game.upgrade_room(selected_slot)
	if error.is_empty():
		tutorial.accepted("upgrade")
	_action(error)

func _sell() -> void:
	if not _tutorial_allow("sell"):
		return
	var error: String = game.sell_room(selected_slot)
	if error.is_empty():
		selected_slot = -1
	_action(error)

func _buy_floor() -> void:
	if not _tutorial_allow("floor"):
		return
	var error: String = game.buy_floor()
	if error.is_empty():
		tutorial.accepted("floor")
	_action(error)
	scroll_position = (game.floor_count - 1) * 160
	if is_instance_valid(floor_scroll):
		floor_scroll.set_deferred("scroll_vertical", scroll_position)

func _heal() -> void:
	if not _tutorial_allow("heal"):
		return
	_action(game.heal_lord())

func _cast_lord_ability() -> void:
	if menu_open or is_instance_valid(modal) or game.phase != "raid":
		return
	if not _tutorial_allow("ability"):
		return
	var error: String = game.cast_ability()
	message = error if not error.is_empty() else str(game.last_action.get("text", "Сила Лорда применена."))
	if error.is_empty():
		if tutorial.step == "ability":
			tutorial.accepted("ability")
			paused = false
			accumulator = 0.0
		_sound("hit")
		if game.phase != "raid":
			_update_record()
	_refresh()

func _start() -> void:
	if not _tutorial_allow("start"):
		return
	selected_slot = -1
	selected_room = ""
	selecting_deal = false
	active_floor = -1
	paused = false
	accumulator = 0.0
	var error: String = game.start_raid()
	if error.is_empty():
		tutorial.accepted("start")
	_action(error)

func _action(error: String) -> void:
	message = error if not error.is_empty() else "Приказ выполнен. Подземелье готовится к рейду."
	_sound("click")
	_refresh()

func _set_speed(value: int) -> void:
	if not _tutorial_allow("speed"):
		return
	speed = value
	_save_settings()
	_refresh()

func _toggle_pause() -> void:
	if not _tutorial_allow("pause"):
		return
	paused = not paused
	_refresh()

func _toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	_sound("click")
	_refresh()

func _show_phase_modal() -> void:
	if menu_open or game.phase not in ["result", "level_up", "floor_choice", "defeat", "blueprint", "relic"]:
		return
	_close_modal()
	var content = _new_modal(940 if game.phase == "level_up" else 640)
	if game.phase in ["blueprint", "relic"]:
		var is_blueprint: bool = game.phase == "blueprint"
		content.add_child(_eyebrow("НАГРАДА ЗА РУБЕЖ"))
		content.add_child(_label("Новый чертёж" if is_blueprint else "Древняя реликвия", 28, GOLD))
		content.add_child(_label("Выберите комнату для магазина этого забега. Она появится в ближайшем предложении." if is_blueprint else "Выберите одно правило, которое усилит вашу сборку до конца забега.", 14, MUTED, true))
		var options: Array = game.blueprint_options() if is_blueprint else game.relic_options()
		for option in options:
			var card = _panel(content)
			var body = _vbox(card, 6)
			var title = HBoxContainer.new()
			body.add_child(title)
			var icon_path: String = str(option.get("icon", ""))
			if not icon_path.is_empty():
				title.add_child(_icon(icon_path, 32))
			var name_label = _label(str(option.name), 19, PAPER, true)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title.add_child(name_label)
			body.add_child(_label(str(option.description), 14, MUTED, true))
			var choose = _button("ВЫБРАТЬ →", _choose_run_reward.bind(str(option.id), is_blueprint))
			body.add_child(choose)
			_tutorial_mark(choose, "choice")
	elif game.phase == "floor_choice":
		content.add_child(_eyebrow("НОВЫЙ ЭТАЖ · НОВЫЕ ВОЗМОЖНОСТИ"))
		content.add_child(_label("Выберите свойство этажа", 26, GOLD))
		content.add_child(_label("Свойство влияет на пять комнат этого этажа и сохраняется до конца забега.", 14, MUTED, true))
		for option in game.floor_trait_options():
			var floor_choice = _button(str(option.name), _choose_floor.bind(str(option.id)))
			content.add_child(floor_choice)
			_tutorial_mark(floor_choice, "choice")
			content.add_child(_label(str(option.description), 13, MUTED, true))
	elif game.phase == "level_up":
		content.add_theme_constant_override("separation", 14)
		content.add_child(_eyebrow("ВЛАДЫКА · УРОВЕНЬ %d" % game.lord.level))
		content.add_child(_label("Какой будет ваша власть?", 28, GOLD))
		content.add_child(_label("Один талант из трёх. Осталось выборов: %d. Эффекты действуют до конца забега." % game.pending_upgrades, 14, MUTED, true))
		var choices = HBoxContainer.new()
		choices.add_theme_constant_override("separation", 12)
		content.add_child(choices)
		for option in game.talent_options():
			_talent_choice_card(choices, option)
		content.add_child(_button("Мои таланты и итоговые бонусы", _show_talents))
	elif game.phase == "result":
		content.add_child(_eyebrow("ПОДЗЕМЕЛЬЕ УСТОЯЛО"))
		content.add_child(_label("Волна %d отражена" % game.wave, 30, GOLD))
		content.add_child(_label("Герои стали частью вашей истории.", 15, MUTED))
		content.add_child(_label("Убито: %d   ·   Золото: +%d   ·   XP: +%d" % [game.report.get("killed", 0), game.report.get("gold", 0), game.report.get("xp", 0)], 17, PAPER, true))
		content.add_child(_label("Здоровье Лорда: %d / %d" % [game.lord.hp, game.lord.max_hp], 15, GOLD))
		content.add_child(_label("Урон Лорду: %d HP\nГерои получили: %d уровней и %d предметов" % [game.report.get("lord_damage", 0), game.report.get("hero_levels", 0), game.report.get("items", 0)], 14, MUTED, true))
		content.add_child(_label("Комнаты восстановлены. Золото и этажи остаются с вами.", 14, MUTED, true))
		if game.pending_upgrades > 0:
			content.add_child(_label("НОВЫЕ ТАЛАНТЫ: %d · выбор после продолжения" % game.pending_upgrades, 15, VIOLET, true))
		var unlock: String = str(game.report.get("unlock", ""))
		if not unlock.is_empty():
			for entry in game.unlock_catalog():
				if str(entry.id) == unlock:
					content.add_child(_label("НОВЫЙ ЧЕРТЁЖ: " + str(entry.name), 19, GREEN, true))
					content.add_child(_label(str(entry.description), 14, MUTED, true))
		var continue_button = _button("ПРОДОЛЖИТЬ →", _next_wave)
		_battle_report_summary(content)
		content.add_child(continue_button)
		_tutorial_mark(continue_button, "continue")
	else:
		if game.tutorial_run:
			content.add_child(_label("Попробуем ещё раз?", 28, GOLD))
			content.add_child(_label("Учебный забег не меняет рекорды, души и постоянные открытия.", 15, MUTED, true))
			content.add_child(_button("Повторить обучение", _begin_tutorial))
			content.add_child(_button("Начать обычную игру", _skip_tutorial))
			return
		content.add_theme_constant_override("separation", 12)
		content.add_child(_eyebrow("ТРОН ПАЛ"))
		content.add_child(_label("Каждое подземелье\nоставляет легенду.", 30, GOLD))
		content.add_child(_label("Пережито волн: %d\nУбито героев: %d\nЭтажей: %d  ·  Уровень Лорда: %d" % [game.cleared_waves, game.total_kills, game.floor_count, game.lord.level], 18, PAPER))
		content.add_child(_label("Рекорд: %d волн. Следующая крепость будет сильнее." % int(profile.get("wave", 0)), 14, MUTED, true))
		var reward: Dictionary = last_run_reward if run_reward_claimed else _pending_run_reward()
		content.add_child(_label("+%d ОСКОЛКОВ ДУШ" % int(reward.get("total", 0)), 23, VIOLET))
		content.add_child(_label(_reward_details(reward), 12, MUTED, true))
		_battle_report_summary(content)
		content.add_child(_button("Лорды · открыть и улучшить", _open_lords))
		content.add_child(_button("Таланты этого забега", _show_talents))
		content.add_child(_button("НОВОЕ ПОДЗЕМЕЛЬЕ", _restart))
		content.add_child(_button("Главное меню", _open_menu))

func _show_help() -> void:
	_close_modal()
	var content = _new_modal(650, true)
	content.add_child(_label("Справочник", 27, GOLD))
	for id in Content.hero_ids():
		var hero: Dictionary = Content.hero(str(id))
		_disclosure(content, str(hero.name), str(hero.get("trait", "")))
	_disclosure(content, "Типы угроз", "Телесные существа уязвимы к рыцарю и варвару. Духи — к чародею. Следопыт ослабляет все ловушки и первый удар засад. Жрица защищает группу от яда. Бард усиливает весь отряд. Признаки комнаты указаны в её подсказке.")
	_disclosure(content, "Управление", "Магазин → пустое место. Комната → другой слот для переноса. Пробел — пауза, Q — сила Лорда, Esc — меню, F11 — полный экран.")
	_disclosure(content, "Развитие комнат · 1 / 5 / 15", "На этих рангах выбирайте развитие в инспекторе комнаты. Выбранные ступени сохраняются до продажи. Последующие выборы добавляют новые свойства к уже выбранным.")
	content.add_child(_button("Комбо комнат и реликвии", _show_run_collection))
	content.add_child(_button("Пройти обучение в игре", _request_tutorial))
	content.add_child(_button("ПОНЯТНО", _close_modal))

func _talent_count() -> int:
	var total: int = 0
	for rank in game.selected_talents.values():
		total += int(rank)
	return total

func _percent(value: float) -> String:
	var amount: int = roundi(value * 100.0)
	return ("+" if amount > 0 else "") + str(amount) + "%"

func _talent_category(id: String) -> String:
	match id:
		"lord": return "ВЛАДЫКА"
		"creatures": return "СУЩЕСТВА"
		"traps": return "ЛОВУШКИ"
		"economy": return "ЭКОНОМИКА"
	return "ТАЛАНТ"

func _talent_color(category: String) -> Color:
	match category:
		"creatures": return GREEN
		"traps": return VIOLET
		"economy": return GOLD
	return PAPER

func _talent_icon(category: String) -> String:
	match category:
		"creatures": return "res://assets/icons/goblin.svg"
		"traps": return "res://assets/icons/spikes.svg"
		"economy": return "res://assets/icons/mimic.svg"
	return "res://assets/icons/lord.svg"

func _talent_choice_card(parent: Control, option: Dictionary) -> void:
	var id: String = str(option.id)
	var category: String = str(option.category)
	var tint: Color = VIOLET if str(option.rarity) == "rare" else _talent_color(category)
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(TILE, tint.darkened(0.4), 10, 14))
	parent.add_child(card)
	var body = _vbox(card, 8)
	var heading = HBoxContainer.new()
	body.add_child(heading)
	heading.add_child(_icon(_talent_icon(category), 28))
	var tag: String = _talent_category(category)
	if str(option.rarity) == "rare":
		tag += " · РЕДКИЙ"
	heading.add_child(_label(tag, 10, tint))
	var title = _label(str(option.name), 20, PAPER, true)
	title.custom_minimum_size.y = 48
	body.add_child(title)
	var rank: int = int(game.selected_talents.get(id, 0))
	var limit: int = int(option.max_rank)
	var rank_text: String = "Ранг %d → %d" % [rank, rank + 1] if rank > 0 else ("Можно брать повторно" if limit != 1 else "Уникальный талант")
	if limit > 1:
		rank_text += " · максимум %d" % limit
	body.add_child(_label(rank_text, 11, tint, true))
	var bonus = _label(str(option.bonus), 14, GREEN, true)
	bonus.custom_minimum_size.y = 54
	body.add_child(bonus)
	var drawback: String = str(option.drawback)
	var penalty = _label(drawback if not drawback.is_empty() else "Без штрафа", 13, RED if not drawback.is_empty() else MUTED, true)
	penalty.custom_minimum_size.y = 44
	body.add_child(penalty)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var preview = _label(_talent_preview(option), 12, tint, true)
	preview.custom_minimum_size.y = 36
	body.add_child(preview)
	var choose = _button("ВЫБРАТЬ  →", _choose_talent.bind(id))
	choose.custom_minimum_size.y = 40
	choose.add_theme_color_override("font_color", tint)
	body.add_child(choose)
	_tutorial_mark(choose, "choice")

func _talent_preview(option: Dictionary) -> String:
	var added: Dictionary = option.modifiers
	var current: Dictionary = game.talent_modifiers()
	var level: int = int(game.lord.level)
	var details: PackedStringArray = []
	if added.has("lord_damage"):
		var damage: int = maxi(1, ceili(float(10 + level - 1) * (1.0 + float(current.get("lord_damage", 0.0)) + float(added.lord_damage))))
		details.append("Урон: %d → %d" % [game.lord.damage, damage])
	if added.has("lord_hp"):
		var hp: int = maxi(1, ceili(float(120 + 10 * (level - 1)) * (1.0 + float(current.get("lord_hp", 0.0)) + float(added.lord_hp))))
		details.append("Макс. HP: %d → %d" % [game.lord.max_hp, hp])
	if added.has("lord_armor"):
		details.append("Броня: %d → %d" % [game.lord.armor, int(game.lord.armor) + int(added.lord_armor)])
	if added.has("floor_cost"):
		var base_cost: int = 5 * (game.floor_count + 1) * (game.floor_count + 1)
		var price: int = maxi(1, ceili(float(base_cost) * (1.0 + float(current.get("floor_cost", 0.0)) + float(added.floor_cost))))
		details.append("Следующий этаж: %d → %d зол." % [game.floor_cost(), price])
	if added.has("kill_gold"):
		var base_gold: int = 3 + floori(float(game.wave - 1) / 3.0)
		var old_gold: int = ceili(float(base_gold) * (1.0 + float(current.get("kill_gold", 0.0))))
		var new_gold: int = ceili(float(base_gold) * (1.0 + float(current.get("kill_gold", 0.0)) + float(added.kill_gold)))
		details.append("За героя сейчас: %d → %d зол." % [old_gold, new_gold])
	if not details.is_empty():
		return "\n".join(details)
	if added.has("opening_strikes"):
		return "Заряды обновляются перед каждой волной."
	if added.has("poison_duration"):
		return "Продлевает яд с учётом этажа и ветки."
	if added.has("monster_damage") or added.has("monster_hp"):
		return "Действует на существ всех этажей."
	return "Усиливает шипы и каждый тик яда."

func _talent_summary(parent: Control) -> void:
	var modifiers: Dictionary = game.talent_modifiers()
	var passive: Dictionary = game.lord_passive_modifiers()
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	var lord_text: String = "%d / %d HP · Урон %d · Броня %d\nОт талантов: HP %s · урон %s" % [maxi(0, int(game.lord.hp)), game.lord.max_hp, game.lord.damage, game.lord.armor, _percent(float(modifiers.get("lord_hp", 0.0))), _percent(float(modifiers.get("lord_damage", 0.0)))]
	if game.selected_talents.has("opening_wrath"):
		lord_text += "\nПервые 3 удара ×2" + (" · осталось %d" % maxi(0, 3 - int(game.lord_strikes)) if game.phase == "raid" else " в каждой волне")
	var creatures_text: String = "HP %s · Урон %s\nОпыт героям за существ %s" % [_percent(float(modifiers.get("monster_hp", 0.0)) + float(passive.get("monster_hp", 0.0))), _percent(float(modifiers.get("monster_damage", 0.0))), _percent(float(modifiers.get("hero_room_xp", 0.0)) + float(passive.get("hero_room_xp", 0.0)))]
	var traps_text: String = "Урон яда %s · Длительность %s\nУрон шипов %s" % [_percent(float(modifiers.get("trap_damage", 0.0))), _percent(float(modifiers.get("poison_duration", 0.0)) + float(passive.get("poison_duration", 0.0))), _percent(float(modifiers.get("trap_damage", 0.0)) + float(modifiers.get("spike_damage", 0.0)))]
	var economy_text: String = "Золото за героев %s\nЭтаж: %d зол. (%s) · Лечение: %d зол. (%s)" % [_percent(float(modifiers.get("kill_gold", 0.0))), game.floor_cost(), _percent(float(modifiers.get("floor_cost", 0.0))), game.heal_cost(), _percent(float(modifiers.get("heal_cost", 0.0)))]
	var summaries: Array[Dictionary] = [
		{"category": "lord", "text": lord_text},
		{"category": "creatures", "text": creatures_text},
		{"category": "traps", "text": traps_text},
		{"category": "economy", "text": economy_text},
	]
	for summary in summaries:
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _style(TILE, LINE, 8, 10))
		grid.add_child(panel)
		var body = _vbox(panel, 5)
		body.add_child(_label(_talent_category(str(summary.category)), 10, _talent_color(str(summary.category))))
		body.add_child(_label(str(summary.text), 12, PAPER, true))

func _show_talents() -> void:
	_close_modal()
	viewing_talents = true
	var body = _new_modal(900)
	body.add_theme_constant_override("separation", 12)
	body.add_child(_label("Таланты Владыки", 28, GOLD))
	body.add_child(_label("Уровень %d · взято %d талантов. Учтена пассивная сила Лорда; этажи и ветки комнат учитываются отдельно." % [game.lord.level, _talent_count()], 13, MUTED, true))
	_talent_summary(body)
	body.add_child(_eyebrow("ВЫБРАНО В ЭТОМ ЗАБЕГЕ"))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 156
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var entries = _vbox(scroll, 10)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if game.selected_talents.is_empty():
		entries.add_child(_label("Первый талант появится на уровне 2. Убивайте героев, чтобы получать опыт, и выбирайте усиления после победы в волне.", 15, MUTED, true))
	for id in Talents.ids():
		var rank: int = int(game.selected_talents.get(id, 0))
		if rank <= 0:
			continue
		var definition: Dictionary = Talents.get_talent(id)
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _style(TILE, LINE, 8, 12))
		entries.add_child(panel)
		var entry = _vbox(panel, 5)
		var title: String = str(definition.name)
		if int(definition.max_rank) != 1:
			title += " · ранг %d" % rank
		entry.add_child(_label(title, 16, _talent_color(str(definition.category)), true))
		entry.add_child(_label(str(definition.bonus) + (" за ранг" if int(definition.max_rank) != 1 else ""), 13, GREEN, true))
		if not str(definition.drawback).is_empty():
			entry.add_child(_label(str(definition.drawback), 12, RED, true))
	body.add_child(_button("Вернуться к выбору" if game.phase == "level_up" else "Назад", _back_from_talents))

func _back_from_talents() -> void:
	_close_modal()
	_show_phase_modal()

func _new_modal(width: int = 560, compact: bool = false) -> VBoxContainer:
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.035, 0.05, 0.88)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_shade.add_child(center)
	modal = PanelContainer.new()
	modal.custom_minimum_size.x = width
	modal.add_theme_stylebox_override("panel", _style(PANEL, Color("#756143"), 16, 28))
	center.add_child(modal)
	var frame = _vbox(modal, 12)
	if tutorial.active() and not menu_open:
		_tutorial_banner(frame)
	elif tutorial.active():
		frame.add_child(_button("Пропустить обучение", _skip_tutorial))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width - 56, minf(460.0 if tutorial.active() else 520.0, get_viewport_rect().size.y - (240.0 if tutorial.active() else 142.0)))
	frame.add_child(scroll)
	var content = _vbox(scroll, 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		scroll.custom_minimum_size.y = 120
		content.minimum_size_changed.connect(_fit_compact_modal.bind(scroll, content))
		_fit_compact_modal.call_deferred(scroll, content)
	return content

func _fit_compact_modal(scroll: ScrollContainer, content: VBoxContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	var height_limit: float = minf(520.0, get_viewport_rect().size.y - (250.0 if tutorial.active() else 160.0))
	scroll.custom_minimum_size.y = clampf(content.get_combined_minimum_size().y, 80.0, maxf(80.0, height_limit))

func _close_modal() -> void:
	if is_instance_valid(modal_shade):
		remove_child(modal_shade)
		modal_shade.queue_free()
	modal = null
	modal_shade = null
	viewing_talents = false

func _next_wave() -> void:
	_close_modal()
	var error: String = game.next_wave()
	if error.is_empty():
		tutorial.accepted("continue")
	_action(error)

func _choose_upgrade(id: String) -> void:
	_choose_talent(id)

func _choose_talent(id: String) -> void:
	_close_modal()
	var error: String = game.choose_talent(id)
	message = error if not error.is_empty() else "Получен талант: %s. Бонусы уже действуют." % str(Talents.get_talent(id).get("name", id))
	_sound("click")
	_refresh()

func _restart() -> void:
	_begin_run()

func _update_record() -> void:
	if demo_mode or not screenshot_path.is_empty() or game.tutorial_run:
		return
	if game.phase == "defeat":
		_settle_run()
	var previous: int = int(profile.get("wave", 0))
	var kills: int = int(profile.get("kills", 0))
	if game.cleared_waves > previous or (game.cleared_waves == previous and game.total_kills > kills):
		profile.wave = game.cleared_waves
		profile.kills = game.total_kills
	profile.floors = maxi(int(profile.get("floors", 1)), game.floor_count)
	profile.level = maxi(int(profile.get("level", 1)), int(game.lord.level))
	profile["unlocked_paths"] = game.unlocked_paths.duplicate()
	_save_profile()

func _save_profile() -> void:
	if demo_mode or not screenshot_path.is_empty():
		return
	profile["lords"] = lords_profile.duplicate(true)
	_write_json("user://profile.json", profile)

func _pending_run_reward() -> Dictionary:
	if game.tutorial_run:
		return {"total": 0, "waves": 0, "kills": 0, "elites": 0, "milestones": 0}
	return LordProgression.reward(game.cleared_waves, game.total_kills, run_best_at_start)

func _settle_run() -> void:
	if not has_run or run_reward_claimed or demo_mode or not screenshot_path.is_empty() or game.tutorial_run:
		return
	last_run_reward = _pending_run_reward()
	lords_profile.souls = int(lords_profile.souls) + int(last_run_reward.total)
	run_reward_claimed = true

func _reward_details(reward: Dictionary) -> String:
	return "Волны: %d · герои: %d · особые отряды: %d · новые рубежи: %d" % [reward.get("waves", 0), reward.get("kills", 0), reward.get("elites", 0), reward.get("milestones", 0)]

func _configure_selected_lord(target) -> void:
	var id: String = str(lords_profile.selected)
	target.configure_lord(id, LordProgression.mastery(lords_profile, id), LordProgression.variant(lords_profile, id))

func _load_local() -> void:
	var loaded: Dictionary = _read_json("user://profile.json")
	for key in ["tutorial_completed", "tutorial_skipped"]:
		profile[key] = loaded.get(key, false) == true
	for key in ["wave", "kills", "floors", "level"]:
		if typeof(loaded.get(key)) in [TYPE_INT, TYPE_FLOAT]:
			profile[key] = maxi(0, int(loaded[key]))
	profile["unlocked_paths"] = []
	if loaded.get("unlocked_paths", []) is Array:
		for unlock in loaded.get("unlocked_paths", []):
			if unlock in ["ambush", "plague"] and not profile.unlocked_paths.has(unlock):
				profile.unlocked_paths.append(unlock)
	lords_profile = LordProgression.sanitize(loaded.get("lords", {}))
	inspected_lord = str(lords_profile.selected)
	var settings: Dictionary = _read_json("user://settings.json")
	sound_on = bool(settings.get("sound", true))
	volume = clampf(float(settings.get("volume", 0.65)), 0.0, 1.0)
	speed = int(settings.get("speed", 1))
	if speed not in [1, 2, 4]:
		speed = 1

func _save_settings() -> void:
	_write_json("user://settings.json", {"schema_version": 1, "sound": sound_on, "speed": tutorial_saved_speed if game.tutorial_run else speed, "volume": volume})

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("schema_version", 0) == 1:
		return data
	return {}

func _write_json(path: String, data: Dictionary) -> void:
	data["schema_version"] = 1
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func _make_sound(kind: String) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var duration: float = 0.065 if kind == "click" else 0.1
	if kind in ["win", "lose"]:
		duration = 0.4
	var count: int = int(22050 * duration)
	var bytes = PackedByteArray()
	bytes.resize(count * 2)
	var freq: float = 440.0
	if kind == "hit":
		freq = 130.0
	if kind == "win":
		freq = 660.0
	if kind == "lose":
		freq = 180.0
	for i in range(count):
		var t: float = float(i) / 22050.0
		var envelope: float = pow(1.0 - float(i) / count, 2.0)
		var sample: int = int(sin(TAU * freq * t) * envelope * 2200.0)
		bytes.encode_s16(i * 2, sample)
	stream.data = bytes
	return stream

func _sound(kind: String) -> void:
	if sound_on and is_instance_valid(audio_player):
		audio_player.volume_db = linear_to_db(maxf(volume, 0.001))
		audio_player.stream = sounds[kind]
		audio_player.play()

func _style(bg: Color, border: Color, radius: int = 8, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _panel(parent: Control, min_width: int = 0) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	panel.add_theme_stylebox_override("panel", _style(PANEL, LINE, 10, 14))
	parent.add_child(panel)
	return panel

func _vbox(parent: Control, spacing: int = 8) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

func _label(text: String, font_size: int = 15, color: Color = PAPER, wrap: bool = false) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _eyebrow(text: String) -> Label:
	return _label(text, 10, GOLD)

func _button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.disabled = disabled
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid():
		button.pressed.connect(callback)
	return button

func _icon(path: String, dimension: int) -> TextureRect:
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(dimension, dimension)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not path.is_empty() and ResourceLoader.exists(path):
		icon.texture = load(path)
	return icon

func _bar(value: float, max_value: float, tint: Color, height: int = 7) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.max_value = maxf(1.0, max_value)
	bar.value = maxf(0.0, value)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", _style(tint, Color.TRANSPARENT, 3, 0))
	return bar

func _stat(parent: Control, title: String, value: String, tint: Color) -> void:
	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 78
	box.add_theme_constant_override("separation", 1)
	parent.add_child(box)
	box.add_child(_label(title, 10, MUTED))
	box.add_child(_label(value, 27, tint))

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _make_demo() -> void:
	_fill_showcase(game)
	message = "Лаборатория продлевает яд. Мастерская усиливает ловушки."
	game.gold = 100
	game.upgrade_room(10)
	game.specialize_room(10, "volley")
	game.upgrade_room(5)
	game.specialize_room(5, "lingering")
	game.gold = 27

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output = get_viewport().get_texture().get_image()
	output.save_png(screenshot_path)
	get_tree().quit()
func _build_menu() -> void:
	var topline = HBoxContainer.new()
	page.add_child(topline)
	var edition = _eyebrow("ЛОРД ПОДЗЕМЕЛЬЯ     /     БЕСКОНЕЧНАЯ ОСАДА")
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topline.add_child(edition)
	topline.add_child(_label("ОСКОЛКИ ДУШ  %d" % int(lords_profile.souls), 12, VIOLET))
	topline.add_child(_label("РЕКОРД  %d ВОЛН" % int(profile.get("wave", 0)), 12, GOLD))
	var main_row = HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 32)
	page.add_child(main_row)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 390
	left.add_theme_constant_override("separation", 10)
	var menu_scroll = ScrollContainer.new()
	menu_scroll.custom_minimum_size.x = 410
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_row.add_child(menu_scroll)
	menu_scroll.add_child(left)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 8
	left.add_child(spacer)
	var selected: Dictionary = Lords.get_lord(str(lords_profile.selected))
	var crown = _icon(str(selected.icon), 64)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(crown)
	left.add_child(_label("ВАШ ТРОН.\nВАШЕ ПОДЗЕМЕЛЬЕ.\nИХ ПОСЛЕДНИЙ РЕЙД.", 29, PAPER))
	var intro = _label("Стройте глубже. Командуйте защитой.\nВмешивайтесь в бой силой своего Лорда.", 14, MUTED, true)
	intro.custom_minimum_size.y = 44
	left.add_child(intro)
	var lords_button = _button("ЛОРДЫ · %s  →" % str(selected.name), _open_lords)
	lords_button.custom_minimum_size.y = 44
	lords_button.add_theme_color_override("font_color", VIOLET)
	left.add_child(lords_button)
	if has_run and game.phase != "defeat":
		var resume = _button("ВЕРНУТЬСЯ · ВОЛНА %d  →" % game.wave, _resume_run)
		resume.custom_minimum_size.y = 38
		left.add_child(resume)
	var start = _button("НОВОЕ ПОДЗЕМЕЛЬЕ  →", _request_new_run)
	start.custom_minimum_size.y = 46
	start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 5, 12))
	start.add_theme_color_override("font_color", INK)
	var first_lesson: bool = not bool(profile.get("tutorial_completed", false)) and not bool(profile.get("tutorial_skipped", false))
	var lesson = _button("НАУЧИТЬСЯ ИГРАЯ →" if first_lesson else "Обучение · сыграть с подсказками", _request_tutorial)
	lesson.custom_minimum_size.y = 42
	if first_lesson:
		lesson.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 5, 10))
		lesson.add_theme_color_override("font_color", INK)
		start.add_theme_stylebox_override("normal", _style(TILE, LINE, 8, 10))
		start.add_theme_color_override("font_color", PAPER)
		left.add_child(lesson)
	left.add_child(start)
	if not first_lesson:
		left.add_child(lesson)
	if tutorial.active():
		left.add_child(_button("Пропустить обучение", _skip_tutorial))
	var actions = HBoxContainer.new()
	left.add_child(actions)
	actions.add_child(_button("Коллекция", _show_collection))
	actions.add_child(_button("Как играть", _show_help))
	actions.add_child(_button("Настройки", _show_settings))
	left.add_child(_button("Выйти из игры", _quit_game))
	var preview_box = _panel(main_row)
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview_col = _vbox(preview_box, 10)
	preview_col.add_child(_eyebrow("ВАШ СЛЕДУЮЩИЙ ПРАВИТЕЛЬ"))
	preview_col.add_child(_label("%s · мастерство %d / 5" % [selected.name, LordProgression.mastery(lords_profile, str(selected.id))], 20, GOLD, true))
	var preview_scroll = ScrollContainer.new()
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_col.add_child(preview_scroll)
	var showcase = Game.new()
	_fill_showcase(showcase)
	menu_preview = DungeonView.new()
	menu_preview.cinematic = true
	menu_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(menu_preview)
	menu_preview.configure(showcase)
	preview_col.add_child(_label("%s\nQ · %s — два заряда на волну." % [selected.passive_description, selected.ability_name], 13, MUTED, true))
	var foot = HBoxContainer.new()
	page.add_child(foot)
	var progress = _label("ЛОРДЫ %d / 3    ·    ВЕТКИ %d / 2    ·    Особые отряды на каждой 5-й волне" % [lords_profile.unlocked.size(), profile.get("unlocked_paths", []).size()], 12, VIOLET)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(progress)
	foot.add_child(_label("%d комнат · %d классов · комбо" % [Content.room_ids().size(), Content.hero_ids().size()], 12, MUTED))

func _open_lords() -> void:
	if not menu_open:
		_open_menu()
	_close_modal()
	menu_section = "lords"
	inspected_lord = str(lords_profile.selected)
	lord_message = ""
	_refresh()

func _leave_lords() -> void:
	_close_modal()
	menu_section = "home"
	_refresh()

func _inspect_lord(id: String) -> void:
	inspected_lord = id
	lord_message = ""
	_refresh()

func _build_lords_page() -> void:
	var heading = HBoxContainer.new()
	page.add_child(heading)
	var titles = _vbox(heading, 3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_eyebrow("КОРОНА ПЕРЕХОДИТ К СЛЕДУЮЩЕМУ"))
	titles.add_child(_label("Лорды подземелья", 30, GOLD))
	_stat(heading, "ОСКОЛКИ ДУШ", str(lords_profile.souls), VIOLET)
	if tutorial.active():
		heading.add_child(_button("Пропустить обучение", _skip_tutorial))
	heading.add_child(_button("Назад", _leave_lords))
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	page.add_child(columns)
	var roster = _vbox(columns, 12)
	roster.custom_minimum_size.x = 285
	for id in Lords.ids():
		_lord_roster_card(roster, id)
	roster.add_child(HSeparator.new())
	roster.add_child(_label("Осколки выдаются за волны, поверженных героев, особые отряды и новые рубежи. Их можно потратить на открытие Лордов или мастерство.", 13, MUTED, true))
	if not last_run_reward.is_empty():
		roster.add_child(_label("Последний забег: +%d осколков" % int(last_run_reward.total), 14, VIOLET, true))
	if has_run and not run_reward_claimed:
		roster.add_child(_label("В текущем забеге заработано: %d. Получите после его завершения." % int(_pending_run_reward().total), 12, MUTED, true))
	var panel = _panel(columns)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var detail = _vbox(scroll, 12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lord_details(detail, inspected_lord)
	var footer = HBoxContainer.new()
	page.add_child(footer)
	var note = _label(lord_message if not lord_message.is_empty() else "Выбор Лорда, мастерство и вариант способности применяются в новом забеге.", 13, VIOLET, true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	var selected: Dictionary = Lords.get_lord(str(lords_profile.selected))
	var start = _button("В БОЙ · %s  →" % str(selected.name), _request_new_run)
	start.custom_minimum_size.y = 44
	footer.add_child(start)

func _lord_roster_card(parent: Control, id: String) -> void:
	var definition: Dictionary = Lords.get_lord(id)
	var owned: bool = lords_profile.unlocked.has(id)
	var chosen: bool = str(lords_profile.selected) == id
	var tint = Color(str(definition.color))
	var button = _button("", _inspect_lord.bind(id))
	button.custom_minimum_size.y = 108
	button.add_theme_stylebox_override("normal", _style(TILE if inspected_lord == id else PANEL, tint if inspected_lord == id else LINE, 10, 10))
	parent.add_child(button)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	button.add_child(margin)
	var row = HBoxContainer.new()
	margin.add_child(row)
	var portrait = _icon(str(definition.icon), 58)
	portrait.modulate.a = 1.0 if owned else 0.5
	row.add_child(portrait)
	var names = _vbox(row, 6)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_label(str(definition.name), 17, tint, true))
	names.add_child(_label("%sМастерство %d / 5" % ["Выбран · " if chosen else "", LordProgression.mastery(lords_profile, id)] if owned else "Открыть: %d осколков" % int(definition.unlock_cost), 11, MUTED, true))
	_ignore_mouse(margin)

func _lord_details(parent: Control, id: String) -> void:
	var definition: Dictionary = Lords.get_lord(id)
	var owned: bool = lords_profile.unlocked.has(id)
	var mastery: int = LordProgression.mastery(lords_profile, id)
	var selected_variant: String = LordProgression.variant(lords_profile, id)
	var tint = Color(str(definition.color))
	var identity = HBoxContainer.new()
	parent.add_child(identity)
	identity.add_child(_icon(str(definition.icon), 80))
	var names = _vbox(identity, 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_label(str(definition.title).to_upper(), 10, tint, true))
	names.add_child(_label(str(definition.name), 29, PAPER, true))
	names.add_child(_label(str(definition.description), 13, MUTED, true))
	parent.add_child(_label("ПАССИВНАЯ СИЛА · " + str(definition.passive_description), 13, tint, true))
	var ability_panel = _panel(parent)
	var ability = _vbox(ability_panel, 6)
	ability.add_child(_label("Q · " + str(definition.ability_name), 21, tint))
	ability.add_child(_label(str(definition.ability_description), 14, PAPER, true))
	ability.add_child(_label(_lord_ability_text(id, mastery, selected_variant), 13, GREEN, true))
	ability.add_child(_label("Два заряда на волну · применяется в текущем бою · работает на паузе", 11, MUTED, true))
	if not owned:
		var price: int = int(definition.unlock_cost)
		parent.add_child(_button("ОТКРЫТЬ И ВЫБРАТЬ · %d ОСКОЛКОВ" % price, _purchase_lord.bind(id), int(lords_profile.souls) < price))
		if int(lords_profile.souls) < price:
			parent.add_child(_label("Нужно ещё %d осколков. Мастерство при открытии: 1." % (price - int(lords_profile.souls)), 12, MUTED, true))
	else:
		parent.add_child(_button("ВЫБРАН ДЛЯ НОВОГО ЗАБЕГА" if str(lords_profile.selected) == id else "ВЫБРАТЬ ЭТОГО ЛОРДА", _select_lord.bind(id), str(lords_profile.selected) == id))
	parent.add_child(HSeparator.new())
	var mastery_row = HBoxContainer.new()
	parent.add_child(mastery_row)
	var mastery_title = _label("МАСТЕРСТВО · %d / 5" % mastery if owned else "МАСТЕРСТВО · ОТКРОЙТЕ ЛОРДА", 12, tint)
	mastery_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_row.add_child(mastery_title)
	for rank in range(1, 6):
		mastery_row.add_child(_label("●" if owned and rank <= mastery else "○", 18, tint if owned and rank <= mastery else MUTED))
	if owned and mastery < Lords.MAX_MASTERY:
		var price: int = Lords.upgrade_cost(mastery)
		parent.add_child(_label("Следующий уровень: " + _mastery_change_text(id, mastery, selected_variant), 13, GREEN, true))
		parent.add_child(_button("ПОВЫСИТЬ МАСТЕРСТВО · %d ОСКОЛКОВ" % price, _upgrade_lord.bind(id), int(lords_profile.souls) < price))
	elif owned:
		parent.add_child(_label("Мастерство полностью развито.", 13, GREEN))
	parent.add_child(_label("ВАРИАНТ СПОСОБНОСТИ · второй открывается на мастерстве 3", 11, MUTED, true))
	var variants = HBoxContainer.new()
	parent.add_child(variants)
	for option in definition.variants:
		var available: bool = owned and mastery >= int(option.min_mastery)
		var is_selected: bool = owned and str(option.id) == selected_variant
		var option_label: String = str(option.name)
		if is_selected:
			option_label += " ✓"
		elif not available:
			option_label += " · ур. %d" % int(option.min_mastery)
		var choose = _button(option_label, _select_lord_variant.bind(id, str(option.id)), not available or is_selected)
		choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choose.tooltip_text = str(option.description)
		variants.add_child(choose)
		if str(option.id) == selected_variant:
			# The description is placed after the buttons, outside their row.
			variants.tooltip_text = str(option.description)
	parent.add_child(_label(variants.tooltip_text, 12, MUTED, true))

func _lord_ability_text(id: String, mastery: int, variant_id: String) -> String:
	var values: Dictionary = Lords.ability_values(id, mastery, variant_id)
	match id:
		"fallen_knight":
			var text: String = "Щит: %d%% максимального HP защитника." % roundi(float(values.shield_fraction) * 100.0)
			if int(values.empowered_attacks) > 0:
				text += " Три следующих удара: %s урона." % _percent(float(values.attack_bonus))
			return text
		"necromancer":
			var text: String = "Одно возвращение с %d%% HP." % roundi(float(values.revive_fraction) * 100.0)
			if float(values.revive_damage_bonus) > 0.0:
				text += " После возвращения: %s урона." % _percent(float(values.revive_damage_bonus))
			return text
		"plague_alchemist":
			var duration: int = ceili(float(values.poison_ticks) * (1.0 + float(values.poison_duration_bonus)))
			return "Яд: %d урона × %d тиков. Вспышка: %d урона. Учтена пассивная сила; таланты забега усиливают длительность." % [values.poison_damage, duration, values.burst_damage]
	return ""

func _mastery_change_text(id: String, mastery: int, variant_id: String) -> String:
	var before: Dictionary = Lords.ability_values(id, mastery, variant_id)
	var after: Dictionary = Lords.ability_values(id, mastery + 1, variant_id)
	var text: String = ""
	match id:
		"fallen_knight":
			text = "щит %d%% → %d%% HP" % [roundi(float(before.shield_fraction) * 100.0), roundi(float(after.shield_fraction) * 100.0)]
			if int(after.empowered_attacks) > 0:
				text += "; усиление ударов %s → %s" % [_percent(float(before.attack_bonus)), _percent(float(after.attack_bonus))]
		"necromancer":
			text = "возвращение с %d%% → %d%% HP" % [roundi(float(before.revive_fraction) * 100.0), roundi(float(after.revive_fraction) * 100.0)]
		"plague_alchemist":
			text = "вспышка %d → %d урона; яд %d → %d, длительность +1 базовый тик" % [before.burst_damage, after.burst_damage, before.poison_damage, after.poison_damage]
	if mastery == 2:
		text += ". Откроется второй вариант способности"
	return text

func _lord_purchase_result(error: String, success: String) -> void:
	lord_message = error if not error.is_empty() else success
	if error.is_empty():
		_save_profile()
		_sound("click")
	_refresh()

func _purchase_lord(id: String) -> void:
	var error: String = LordProgression.purchase(lords_profile, id)
	if error.is_empty():
		LordProgression.select(lords_profile, id)
	_lord_purchase_result(error, "%s открыт и выбран для нового забега." % str(Lords.get_lord(id).get("name", id)))

func _select_lord(id: String) -> void:
	_lord_purchase_result(LordProgression.select(lords_profile, id), "Лорд выбран. Новый правитель вступит в бой в следующем забеге.")

func _upgrade_lord(id: String) -> void:
	var error: String = LordProgression.upgrade(lords_profile, id)
	_lord_purchase_result(error, "Мастерство повышено до %d. Усиление действует со следующего забега." % LordProgression.mastery(lords_profile, id))

func _select_lord_variant(id: String, variant_id: String) -> void:
	_lord_purchase_result(LordProgression.select_variant(lords_profile, id, variant_id), "Вариант способности выбран для следующего забега.")

func _request_new_run() -> void:
	if has_run and game.phase != "defeat":
		_close_modal()
		var body = _new_modal()
		body.add_child(_label("Начать новое подземелье?", 26, GOLD))
		body.add_child(_label("Текущий забег закончится. Получите %d осколков душ за достигнутые результаты. Новый Лорд: %s." % [int(_pending_run_reward().total), str(Lords.get_lord(str(lords_profile.selected)).name)], 16, MUTED, true))
		body.add_child(_button("НАЧАТЬ НОВЫЙ ЗАБЕГ", _begin_run))
		body.add_child(_button("Вернуться", _close_modal))
	else:
		_begin_run()

func _begin_run() -> void:
	_close_modal()
	selecting_deal = false
	if tutorial.active():
		_end_tutorial(false)
	if has_run:
		_settle_run()
		_update_record()
	game.unlocked_paths.assign(profile.get("unlocked_paths", []))
	game.restart()
	_configure_selected_lord(game)
	run_best_at_start = int(profile.get("wave", 0))
	run_reward_claimed = false
	last_run_reward = {}
	menu_open = false
	menu_section = "home"
	has_run = true
	paused = false
	resume_paused = false
	accumulator = 0.0
	selected_slot = -1
	selected_room = ""
	scroll_position = 0
	active_floor = -1
	message = "%s: %s" % [game.lord.name, Lords.get_lord(game.lord_archetype).passive_description]
	_sound("click")
	_refresh()

func _open_menu() -> void:
	if menu_open:
		return
	resume_paused = paused
	paused = true
	menu_open = true
	menu_section = "home"
	_close_modal()
	_refresh()

func _resume_run() -> void:
	if not has_run or game.phase == "defeat":
		return
	_close_modal()
	menu_open = false
	menu_section = "home"
	paused = resume_paused
	_refresh()

func _show_collection() -> void:
	_close_modal()
	var body = _new_modal(610, true)
	body.add_child(_label("Постоянные открытия", 26, GOLD))
	for entry in game.unlock_catalog():
		var unlocked: bool = profile.get("unlocked_paths", []).has(str(entry.id))
		_disclosure(body, str(entry.name), str(entry.description) + "\nОткрывается победой на волне %d и остаётся в следующих забегах." % int(entry.wave), "Открыто" if unlocked else "Волна %d" % int(entry.wave), GREEN if unlocked else GOLD)
	body.add_child(_button("Комбо и находки текущего забега", _show_run_collection))
	body.add_child(_button("Назад", _close_modal))

func _show_settings() -> void:
	_close_modal()
	var body = _new_modal()
	body.add_child(_label("Настройки", 28, GOLD))
	body.add_child(_button("Полный экран / окно · F11", _toggle_fullscreen))
	body.add_child(_button("Звук: " + ("включён" if sound_on else "выключен"), _settings_toggle_sound))
	body.add_child(_label("Громкость", 15, MUTED))
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume
	slider.value_changed.connect(_set_volume)
	body.add_child(slider)
	body.add_child(_label("Скорость просмотра рейда", 15, MUTED))
	var buttons = HBoxContainer.new()
	body.add_child(buttons)
	for value in [1, 2, 4]:
		buttons.add_child(_button("×%d%s" % [value, " ✓" if speed == value else ""], _settings_speed.bind(value)))
	body.add_child(_button("Готово", _close_modal))

func _settings_toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	_sound("click")
	_show_settings()

func _settings_speed(value: int) -> void:
	speed = value
	_save_settings()
	_show_settings()

func _set_volume(value: float) -> void:
	volume = value
	_save_settings()

func _exit_tree() -> void:
	if is_instance_valid(dungeon_view) and dungeon_view.get_parent() == null:
		dungeon_view.free()

func _quit_game() -> void:
	if has_run:
		_settle_run()
		_update_record()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

func _fill_showcase(target) -> void:
	target.restart(2042)
	_configure_selected_lord(target)
	target.gold = 500
	target.buy_floor()
	target.choose_floor_trait("laboratory")
	target.buy_floor()
	target.choose_floor_trait("workshop")
	var layout: Array[String] = ["goblin", "executioner", "spider", "mimic", "goblin", "poison", "spider", "poison", "spider", "executioner", "spikes", "spikes", "mimic", "poison", "executioner"]
	for index in range(layout.size()):
		target.shop[layout[index]] = 10
		target.buy_room(index, layout[index])
	target.wave = 8
	target._generate_party()
	target._generate_shop()
	target.gold = 27
func _matchup_text(stats: Dictionary) -> String:
	match str(stats.get("id", "")):
		"mimic":
			return "Цель: бард, жрица, чародей — поддержка за передним бойцом. Живой следопыт ослабляет первый удар засады на 35%."
		"spider":
			return "Цель: ослабленный герой. Яд усиливает укус."
		"ogre":
			return "Каждый третий удар ×1,5. Долгий бой помогает нанести тяжёлый удар."
		"war_hound":
			return "Охотится на слабейшего; +30% урона целям с HP ≤ 40%."
		"wraith":
			return "Игнорирует 2 брони. Рыцарь и варвар наносят духам на 20% меньше урона; чародей — на 25% больше без безмолвия."
		"vampire":
			return "Если пережил ответ, лечится на 25% реально нанесённого урона."
		"ballista", "blade_floor":
			return str(stats.get("role", "")) + " Следопыт ослабит ловушку, пока есть инструменты."
		"spikes":
			return "Следопыт ослабит ловушку, пока есть инструменты. Заставьте его потратить их раньше."
		"poison":
			return "Следопыт сокращает отравление за инструмент. Жрица снижает урон яда всей группе на 25%, пока жива и не заглушена."
		"shackles":
			return "Задерживает атаки в следующем бою. Соседний страж дополняет оковы связкой «Темница»."
		"silence":
			return "Подавляет магию чародея, лечение и защиту от яда жрицы, песню барда. Следопыт может сократить эффект. Ярость варвара сохраняется."
		"rust":
			return "Ослабляет броню группы перед следующим боем. Поставьте перед сильным существом."
		"guardian":
			return "Удерживает героев: дайте яду время. Оковы перед стражем образуют «Темницу»."
		_:
			return "Рыцарь и варвар сильны против телесных существ. Ловушки, духи и нападение на поддержку ослабят их группу."

func _show_specializations(index: int) -> void:
	if not _tutorial_allow("evolution"):
		return
	var options: Array = game.room_evolution_options(index)
	if options.is_empty():
		return
	_close_modal()
	var content = _new_modal(620, true)
	content.add_child(_eyebrow("РАЗВИТИЕ · РАНГ %d" % int(options[0].get("tier", 1))))
	content.add_child(_label(str(game.room_stats(index).name), 26, GOLD, true))
	for option in options:
		var card = _panel(content)
		var details = _vbox(card, 6)
		details.add_child(_label(str(option.name), 18, PAPER, true))
		details.add_child(_label(str(option.description), 13, MUTED, true))
		var choose = _button("Выбрать →", _specialize.bind(index, str(option.id)))
		details.add_child(choose)
		_tutorial_mark(choose, "evolution_choice")
	content.add_child(_button("Выбрать позже", _close_modal))

func _specialize(index: int, id: String) -> void:
	if not _tutorial_allow("evolution_choice"):
		return
	_close_modal()
	var error: String = game.choose_room_evolution(index, id)
	if error.is_empty():
		tutorial.accepted("evolution_choice")
	_action(error)

func _choose_floor(id: String) -> void:
	_close_modal()
	var error: String = game.choose_floor_trait(id)
	if error.is_empty():
		tutorial.accepted("floor_choice")
	_action(error)


func _choose_run_reward(id: String, blueprint: bool) -> void:
	_close_modal()
	var error: String = game.choose_blueprint(id) if blueprint else game.choose_relic(id)
	_action(error)


func _hero_status(hero: Dictionary, definition: Dictionary) -> String:
	if int(hero.hp) <= 0:
		return "Повержен"
	var parts: PackedStringArray = []
	match str(hero.id):
		"knight":
			parts.append("Силен против телесных · слаб против духов")
		"rogue":
			parts.append("Инструменты: %d · все ловушки · раскрывает засады" % int(hero.get("disarm_charges", 2)))
		"priest":
			parts.append("Лечение · защита группы от яда −25%" if int(hero.get("silence_ticks", 0)) <= 0 else "Лечение и защита от яда заглушены")
		"mage":
			parts.append("Против духов +25% · заклинание каждый 3-й тик" if int(hero.get("silence_ticks", 0)) <= 0 else "Магия заглушена")
		"barbarian":
			parts.append("Телесные +20% · духи −20%")
			parts.append("ЯРОСТЬ +25%" if int(hero.hp) <= float(hero.max_hp) * 0.4 else "Ярость при HP ≤ 40%")
		"bard":
			parts.append("Песня: +15% урона всему отряду" if int(hero.get("silence_ticks", 0)) <= 0 else "Песня заглушена")
		_:
			parts.append(str(definition.get("trait", "")))
	if int(hero.get("poison_ticks", 0)) > 0:
		parts.append("Яд: %d т." % int(hero.poison_ticks))
	for effect in ["shackles", "silence", "rust"]:
		var current: int = int(hero.get(effect + "_ticks", 0))
		var pending: int = int(hero.get("pending_" + effect, 0))
		var names: Dictionary = {"shackles": "Оковы", "silence": "Безмолвие", "rust": "Ржавчина"}
		if current > 0:
			parts.append("%s: %d т." % [names[effect], current])
		elif pending > 0:
			parts.append("%s → следующий бой" % names[effect])
	if int(hero.get("goblin_mark_slot", -1)) >= 0:
		parts.append("Метка засады")
	return " · ".join(parts)


func _room_combo_details(parent: Control, index: int) -> void:
	var link: Dictionary = game.room_combo(index)
	if not link.is_empty():
		_disclosure(parent, str(link.name), str(link.description), "Комбо", GOLD)
		return
	var room_id: String = str(game.rooms[index].get("id", ""))
	for combo in game.combo_catalog():
		if room_id == str(combo.first):
			_disclosure(parent, str(combo.name), "Поставьте следующей: %s. Соседние места одного этажа по стрелкам пути.\n%s" % [Content.room(str(combo.second)).name, combo.description], "Нет пары", MUTED)
		elif room_id == str(combo.second):
			_disclosure(parent, str(combo.name), "Поставьте перед этой: %s. Соседние места одного этажа по стрелкам пути.\n%s" % [Content.room(str(combo.first)).name, combo.description], "Нет пары", MUTED)


func _show_run_collection() -> void:
	_close_modal()
	var body = _new_modal(690, true)
	body.add_child(_label("Моя сборка", 28, GOLD))
	_faction_counters(body)
	_disclosure(body, "Правила фракций и комбо", "Фракции считают разные типы построенных комнат: копии одного типа не добавляют счётчик.\nКомбо связывают соседние места одного этажа по направлению героев. Пустое место или лестница разрывает связку.")
	body.add_child(_eyebrow("КОМБО"))
	for combo in game.combo_catalog():
		var count: int = 0
		for link in game.active_combos():
			if str(link.id) == str(combo.id):
				count += 1
		_disclosure(body, "%s → %s" % [Content.room(str(combo.first)).short_name, Content.room(str(combo.second)).short_name], str(combo.name) + "\n" + str(combo.description), "Активно %d" % count if count > 0 else "Нет пары", GOLD if count > 0 else MUTED)
	body.add_child(HSeparator.new())
	body.add_child(_eyebrow("ЧЕРТЕЖИ ЭТОГО ЗАБЕГА"))
	if game.selected_blueprints.is_empty():
		_disclosure(body, "Пока нет", "Выбор после каждой 7-й волны, пока есть неизученные комнаты. Чертежи не повторяются; в новом забеге открытия начинаются заново.", "Каждые 7 волн", MUTED)
	for id in game.selected_blueprints:
		var room: Dictionary = Content.room(str(id))
		_disclosure(body, str(room.name), str(room.description), "В магазине", GREEN)
	body.add_child(_eyebrow("РЕЛИКВИИ ЭТОГО ЗАБЕГА"))
	if game.selected_relics.is_empty():
		_disclosure(body, "Пока нет", "После каждой %d-й волны — одна из ещё не изученных реликвий. Действует до конца забега." % Game.RELIC_WAVE_INTERVAL, "Каждые %d волн" % Game.RELIC_WAVE_INTERVAL, MUTED)
	for relic in game.relic_definitions():
		if game.selected_relics.has(str(relic.id)):
			_disclosure(body, str(relic.name), str(relic.description), "Активна", VIOLET)
	body.add_child(_button("Назад", _back_from_talents))


func _style_faction_card(button: Button, color: Color, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill: Color = Color("#343127") if selected else TILE
		if state == "hover":
			fill = Color("#303a49")
		elif state == "disabled":
			fill = Color("#181e27")
		elif state == "focus":
			fill = Color.TRANSPARENT
		var card_style = _style(fill, color, 9, 10)
		card_style.set_border_width_all(3 if selected else 2)
		button.add_theme_stylebox_override(state, card_style)


func _faction_counters(parent: Control) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	for faction in game.faction_status():
		var thresholds: Array = faction.get("thresholds", [2, 3])
		var next_threshold: int = int(thresholds.back()) if not thresholds.is_empty() else 3
		for threshold in thresholds:
			if int(faction.count) < int(threshold):
				next_threshold = int(threshold)
				break
		var count_text: String = "%d/%d" % [faction.count, next_threshold] if int(faction.count) < next_threshold else "%d ✓" % int(faction.count)
		var button = _button("%s %s" % [faction.name, count_text], _show_factions)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 11)
		button.custom_minimum_size.y = 30
		var tint: Color = faction.color
		button.add_theme_stylebox_override("normal", _style(TILE, tint, 6, 6))
		button.add_theme_color_override("font_color", tint)
		button.tooltip_text = _faction_rules(faction)
		row.add_child(button)


func _faction_rules(faction: Dictionary) -> String:
	var lines: PackedStringArray = ["Считаются разные типы на поле, а не количество копий."]
	var names: PackedStringArray = []
	for id in faction.get("room_ids", []):
		names.append(str(Content.room(str(id)).get("short_name", id)))
	if not names.is_empty():
		lines.append("Комнаты: " + ", ".join(names))
	for bonus in faction.get("bonuses", []):
		lines.append(("✓ " if bool(bonus.get("active", false)) else "") + str(bonus.get("description", "")))
	return "\n".join(lines)


func _show_factions() -> void:
	_close_modal()
	var content = _new_modal(640, true)
	content.add_child(_label("Фракции подземелья", 26, GOLD))
	for faction in game.faction_status():
		var panel = _panel(content)
		var tint: Color = faction.color
		panel.add_theme_stylebox_override("panel", _style(TILE, tint, 8, 12))
		var body = _vbox(panel, 6)
		body.add_child(_label("%s · %d разных типа" % [faction.name, faction.count], 18, tint, true))
		body.add_child(_label(_faction_rules(faction), 13, MUTED, true))
	content.add_child(_button("Назад", _back_from_talents))


func _room_progression_details(parent: Control, index: int) -> void:
	var progression: Dictionary = game.room_progression(index)
	var stages: PackedStringArray = []
	var descriptions: PackedStringArray = []
	var chosen_names: PackedStringArray = []
	for stage in progression.get("stages", []):
		var chosen: bool = bool(stage.get("chosen", false))
		if chosen:
			chosen_names.append(str(stage.get("name", "")))
		stages.append("%s%d" % ["✓" if chosen else "◇" if bool(stage.get("available", false)) else "", int(stage.get("tier", 0))])
		descriptions.append("Ранг %d · %s" % [int(stage.get("tier", 0)), str(stage.get("name", "Выбор впереди")) if chosen else "Выбор доступен" if bool(stage.get("available", false)) else "Ещё не достигнут"])
		if chosen and not str(stage.get("description", "")).is_empty():
			descriptions.append(str(stage.description))
	var next_tier: int = int(progression.get("next_tier", 0))
	if not chosen_names.is_empty():
		parent.add_child(_label(" → ".join(chosen_names), 12, VIOLET, true))
	_disclosure(parent, "Развитие · " + " / ".join(stages), "\n".join(descriptions), "Готово" if next_tier == 0 else "След. %d" % next_tier, VIOLET)


func _deal_card(parent: Control, offer: Dictionary) -> void:
	var column = _vbox(parent, 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var definition: Dictionary = Content.room(str(offer.get("room_id", "")))
	var accepted: bool = bool(offer.get("accepted", false))
	var label: String = "Сделка принята · " if accepted else "✓ Разместить · " if selecting_deal else "Сделка · "
	label += "%s · ранг %d · %d зол." % [definition.get("short_name", "Комната"), int(offer.get("rank", 3)), int(offer.get("price", 0))]
	var button = _button(label, _select_deal, accepted or not bool(offer.get("available", false)) or game.gold < int(offer.get("price", 0)))
	button.add_theme_font_size_override("font_size", 12)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var faction: Dictionary = Game.room_faction(str(offer.get("room_id", "")))
	_style_faction_card(button, faction.get("color", GOLD), selecting_deal)
	button.tooltip_text = Content.room_traits_text(definition) + "\n" + str(offer.get("description", "")) + "\n" + str(offer.get("risk_text", "")) + "\nРанг растёт с номером волны. Отмена выбора не меняет предложение.\nДо начала волны продажа этой комнаты снимает риск."
	column.add_child(button)
	column.add_child(_label(str(offer.get("risk_text", "")), 11, RED, true))


func _select_deal() -> void:
	if game.phase != "prepare" or not _tutorial_allow("deal"):
		return
	var offer: Dictionary = game.deal_offer()
	if offer.is_empty() or not bool(offer.get("available", false)) or bool(offer.get("accepted", false)):
		return
	selecting_deal = not selecting_deal
	selected_room = ""
	selected_slot = -1
	message = "Выберите свободное место для комнаты по сделке." if selecting_deal else "Размещение сделки отменено."
	_sound("click")
	_refresh()


func _disclosure(parent: Control, title: String, details: String, status: String = "", tint: Color = MUTED) -> void:
	var column = _vbox(parent, 4)
	var button = _button("▸ " + title + (" · " + status if not status.is_empty() else ""), Callable())
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", tint)
	button.tooltip_text = details
	column.add_child(button)
	var description = _label(details, 12, MUTED, true)
	description.visible = false
	column.add_child(description)
	button.toggled.connect(func(opened: bool):
		description.visible = opened
		button.text = ("▾ " if opened else "▸ ") + title + (" · " + status if not status.is_empty() else "")
	)


func _battle_report_summary(parent: Control) -> void:
	var entries: Array = game.battle_room_report()
	if entries.is_empty():
		return
	var best: Dictionary = {}
	var best_control: Dictionary = {}
	for entry in entries:
		if int(entry.get("damage", 0)) > 0 and (best.is_empty() or int(entry.get("damage", 0)) > int(best.get("damage", 0))):
			best = entry
		if int(entry.get("control_actions", 0)) > 0 and (best_control.is_empty() or int(entry.get("control_actions", 0)) > int(best_control.get("control_actions", 0))):
			best_control = entry
	if not best.is_empty():
		parent.add_child(_label("Больше всего урона: %s · %d" % [best.get("name", "Комната"), int(best.get("damage", 0))], 13, GREEN, true))
	if not best_control.is_empty():
		parent.add_child(_label("Больше всего контроля: %s · %d" % [best_control.get("name", "Комната"), int(best_control.get("control_actions", 0))], 13, VIOLET, true))
	parent.add_child(_button("Вклад каждой комнаты →", _show_battle_report))


func _show_battle_report() -> void:
	_close_modal()
	var content = _new_modal(680, true)
	content.add_child(_label("Вклад комнат", 27, GOLD))
	content.add_child(_label(("Текущий бой" if game.phase == "raid" else "Последний бой") + " · фактические результаты", 12, MUTED))
	for entry in game.battle_room_report():
		var slot: int = int(entry.get("slot", -1))
		var location: String = "Этаж %d · место %d" % [slot / 5 + 1, slot % 5 + 1] if slot >= 0 and str(entry.get("room_id", "")) != "lord" else "Трон"
		var card = _panel(content)
		var body = _vbox(card, 5)
		body.add_child(_label("%s · %s" % [location, entry.get("name", "Комната")], 15, PAPER, true))
		if not bool(entry.get("visited", false)):
			body.add_child(_label("Герои не дошли", 12, MUTED))
			if int(entry.get("damage", 0)) == 0 and int(entry.get("kills", 0)) == 0 and int(entry.get("control_actions", 0)) == 0:
				continue
		var combo_value: Variant = entry.get("combos", 0)
		var combo_count: int = combo_value.size() if combo_value is Array else int(combo_value)
		body.add_child(_label("Урон %d  ·  Убийства %d  ·  Тики %d\nКонтроль %d  ·  Комбо %d" % [int(entry.get("damage", 0)), int(entry.get("kills", 0)), int(entry.get("ticks", 0)), int(entry.get("control_actions", 0)), combo_count], 13, GREEN, true))
	_disclosure(content, "Что означают показатели", "Урон — реально снятые HP, включая отложенный яд от этой комнаты. Убийства — добитые герои. Тики — время столкновения. Контроль — пропуски атак, подавленные способности и удары по ослабленной броне. Комбо — срабатывания связок у комнаты, получившей бонус. «Герои не дошли» означает отсутствие прямого боя; сила Лорда может принести вклад раньше встречи с троном.")
	content.add_child(_button("Назад", _back_from_talents))


func _tutorial_context(parent: Control, area: String) -> void:
	var hint: Dictionary = tutorial.context_hint(area)
	if hint.is_empty():
		return
	var panel = _panel(parent)
	panel.add_theme_stylebox_override("panel", _style(Color("#29271f"), GOLD, 8, 9))
	var body = _vbox(panel, 5)
	body.add_child(_label(str(hint.get("title", "Подсказка")), 12, GOLD, true))
	body.add_child(_label(str(hint.get("text", "")), 12, PAPER, true))


func _tutorial_slot() -> int:
	if tutorial.active() and not menu_open:
		var target: String = tutorial.target()
		if target.begins_with("slot:"):
			return int(target.trim_prefix("slot:"))
	return -1


func _tutorial_mark(button: Button, action: String) -> void:
	if not tutorial.active() or menu_open:
		return
	if action not in ["choice", "continue"] and not tutorial.allows(action):
		button.disabled = true
	if (action == tutorial.target() or (action == "evolution_choice" and tutorial.step == "evolution")) and not button.disabled:
		var border = _style(Color("#353025"), GOLD, 8, 10)
		border.set_border_width_all(3)
		button.add_theme_stylebox_override("normal", border)
		button.add_theme_color_override("font_color", GOLD)
		button.tooltip_text = tutorial.prompt(str(game.phase)) + "\n" + button.tooltip_text


func _tutorial_allow(action: String) -> bool:
	if tutorial.allows(action):
		return true
	message = "Сейчас выполните подсвеченный шаг. «Пропустить» начинает обычную игру."
	_refresh()
	return false


func _tutorial_banner(parent: Control) -> void:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("#29271f"), GOLD, 8, 9))
	parent.add_child(panel)
	var row = HBoxContainer.new()
	panel.add_child(row)
	var caption = _label("ОБУЧЕНИЕ  ·  " + tutorial.prompt(str(game.phase)), 14, GOLD, true)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	if tutorial.step == "finish":
		row.add_child(_button("МОЙ ЗАБЕГ →", _complete_tutorial))
	row.add_child(_button("Пропустить", _skip_tutorial))


func _request_tutorial() -> void:
	_close_modal()
	if has_run and game.phase != "defeat" and not game.tutorial_run:
		var body = _new_modal()
		body.add_child(_label("Начать учебное подземелье?", 26, GOLD, true))
		body.add_child(_label("Текущий забег закончится; его %d душ будут сохранены. В обучении — отдельное золото, без душ и рекордов. Прошлые достижения останутся с вами." % int(_pending_run_reward().total), 15, MUTED, true))
		body.add_child(_button("Начать обучение", _begin_tutorial))
		body.add_child(_button("Вернуться", _back_from_talents))
	else:
		_begin_tutorial()


func _begin_tutorial() -> void:
	_close_modal()
	selecting_deal = false
	if has_run:
		_settle_run()
		_update_record()
	if not game.tutorial_run:
		tutorial_saved_speed = speed
	game.begin_tutorial()
	tutorial.begin()
	speed = 1
	has_run = true
	menu_open = false
	menu_section = "home"
	paused = false
	resume_paused = false
	accumulator = 0.0
	selected_slot = -1
	selected_room = ""
	scroll_position = 0
	active_floor = -1
	run_reward_claimed = true
	last_run_reward = {}
	message = "Учебные ресурсы действуют только здесь. Следуйте золотой подсветке."
	_refresh()


func _end_tutorial(completed: bool) -> void:
	if not tutorial.active():
		return
	profile["tutorial_completed" if completed else "tutorial_skipped"] = true
	tutorial.step = ""
	speed = tutorial_saved_speed
	if is_instance_valid(dungeon_view):
		dungeon_view.tutorial_slot = -1
	_save_profile()


func _complete_tutorial() -> void:
	_end_tutorial(true)
	_begin_run()


func _skip_tutorial() -> void:
	_end_tutorial(false)
	_begin_run()
