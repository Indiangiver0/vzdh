extends PanelContainer
## The screen receives a model snapshot; selecting a node never purchases it.
signal purchase_requested(id: String)
signal close_requested
const SkillMap = preload("res://scripts/run_skill_map.gd")
const PAPER = Color("#ede5d5")
const MUTED = Color("#a0acbb")
const GOLD = Color("#dfba70")
const GREEN = Color("#83bfa6")
const CATEGORY_NAMES = {"lord": "Лорд", "creatures": "Существа", "traps": "Ловушки", "poison": "Яды", "economy": "Экономика", "ritual": "Ритуалы Q", "shared": "Общие навыки"}
var selected_id: String = "root"
var map: Control
var _nodes: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _souls: int = 0
var _can_purchase: bool = false
var _phase: String = "prepare"
var _wallet: Button
var _drop_info: String = ""
var _hint: Label
var _zoom: Label
var _zoom_slider: HSlider
var _navigation: BoxContainer
var _zoom_controls: HBoxContainer
var _camera_actions: HBoxContainer
var _title: Label
var _category: Label
var _description: RichTextLabel
var _requires: VBoxContainer
var _buy: Button
var _body: BoxContainer
var _sidebar: PanelContainer
var _detail_scroll: ScrollContainer
var _picker: OptionButton
var _search: LineEdit
var _root_box: VBoxContainer
var _toolbar: HBoxContainer
var _heading: Label
var _map_frame: VBoxContainer
var _detail_toggle: Button
var _details_only: bool = false
var _fit_button: Button

func _ready() -> void:
	set_meta("progression_tree", true)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151c26")
	style.border_color = Color("#5a5140")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)
	_root_box = VBoxContainer.new()
	_root_box.add_theme_constant_override("separation", 8)
	add_child(_root_box)
	var header := HBoxContainer.new()
	_root_box.add_child(header)
	header.add_child(_button("Назад", func(): close_requested.emit()))
	var heading: Label = _label("Навыки", 23, GOLD)
	_heading = heading
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_detail_toggle = _button("Описание", _toggle_details)
	header.add_child(_detail_toggle)
	_wallet = _button("", func():
		map.set_selection("root")
		_select("root"))
	_wallet.add_theme_color_override("font_color", GREEN)
	header.add_child(_wallet)
	_hint = _label("", 12, MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_box.add_child(_hint)
	var toolbar := HBoxContainer.new()
	_toolbar = toolbar
	_root_box.add_child(toolbar)
	_search = LineEdit.new()
	_search.placeholder_text = "Найти навык…"
	_search.custom_minimum_size.x = 110
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(_search_changed)
	_search.text_submitted.connect(func(_query): _pick_result(0))
	toolbar.add_child(_search)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.x = 150
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.item_selected.connect(_pick_result)
	toolbar.add_child(_picker)
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_root_box.add_child(_body)
	var map_frame := VBoxContainer.new()
	_map_frame = map_frame
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(map_frame)
	map = SkillMap.new()
	map.custom_minimum_size = Vector2(160, 130)
	map.node_selected.connect(_select)
	map.camera_changed.connect(_camera_changed)
	map_frame.add_child(map)
	_navigation = BoxContainer.new()
	_navigation.add_theme_constant_override("separation", 8)
	map_frame.add_child(_navigation)
	_zoom_controls = HBoxContainer.new()
	_zoom_controls.add_theme_constant_override("separation", 6)
	_zoom_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_navigation.add_child(_zoom_controls)
	var zoom_out: Button = _button("−", func(): map.zoom_by(1.0 / 1.25))
	zoom_out.custom_minimum_size.x = 36
	zoom_out.tooltip_text = "Отдалить карту"
	_zoom_controls.add_child(zoom_out)
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 0.0
	_zoom_slider.max_value = 1.0
	_zoom_slider.step = 0.0
	_zoom_slider.custom_minimum_size = Vector2(64, 36)
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.focus_mode = Control.FOCUS_ALL
	_zoom_slider.tooltip_text = "Масштаб карты: перетащите ползунок или нажмите ← / →"
	_zoom_slider.value_changed.connect(_zoom_slider_changed)
	_zoom_slider.gui_input.connect(_zoom_slider_input)
	_zoom_controls.add_child(_zoom_slider)
	var zoom_in: Button = _button("+", func(): map.zoom_by(1.25))
	zoom_in.custom_minimum_size.x = 36
	zoom_in.tooltip_text = "Приблизить карту"
	_zoom_controls.add_child(zoom_in)
	_zoom = _label("", 12, MUTED)
	_zoom.custom_minimum_size.x = 54
	_zoom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_controls.add_child(_zoom)
	_camera_actions = HBoxContainer.new()
	_camera_actions.alignment = BoxContainer.ALIGNMENT_END
	_navigation.add_child(_camera_actions)
	_camera_actions.add_child(_button("Центр", func(): map.reset_center()))
	_fit_button = _button("Всё дерево", func(): map.fit_all())
	_fit_button.tooltip_text = "Показать всё дерево"
	_camera_actions.add_child(_fit_button)
	_camera_changed(map.zoom)
	map_frame.resized.connect(_layout_navigation)
	_sidebar = PanelContainer.new()
	_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_sidebar)
	var detail_box := VBoxContainer.new()
	_sidebar.add_child(detail_box)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.add_child(_detail_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 10)
	_detail_scroll.add_child(details)
	_category = _label("", 12, MUTED)
	details.add_child(_category)
	_title = _label("", 23, GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_title)
	_description = RichTextLabel.new()
	_description.fit_content = true
	_description.scroll_active = false
	_description.bbcode_enabled = false
	_description.add_theme_font_size_override("normal_font_size", 14)
	_description.add_theme_color_override("default_color", PAPER)
	details.add_child(_description)
	_requires = VBoxContainer.new()
	details.add_child(_requires)
	_buy = _button("Выберите навык", func(): purchase_requested.emit(selected_id))
	_buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buy.custom_minimum_size.y = 46
	detail_box.add_child(_buy)
	resized.connect(_layout)
	_layout()
	_refresh()

func configure(nodes: Array[Dictionary], souls: int, phase: String, selected: String = "") -> void:
	_nodes = nodes.duplicate(true)
	_by_id.clear()
	for node in _nodes:
		_by_id[str(node.id)] = node
	_souls = souls
	_phase = phase
	_can_purchase = phase == "prepare"
	if not selected.is_empty():
		selected_id = selected
	if is_instance_valid(map):
		_refresh()

func configure_drop_info(ordinary: Dictionary, special: Dictionary, failures: int) -> void:
	_drop_info = "Текущие шансы:\nОбычный герой: %d%% — 0, %d%% — 1 душа.\nОсобый герой: %d%% — 0, %d%% — 1, %d%% — 2 души.\nНулевых наград подряд: %d / 2." % [roundi(float(ordinary.get("0", 0)) * 100), roundi(float(ordinary.get("1", 0)) * 100), roundi(float(special.get("0", 0)) * 100), roundi(float(special.get("1", 0)) * 100), roundi(float(special.get("2", 0)) * 100), failures]
	if bool(ordinary.get("guaranteed", false)):
		_drop_info += " Следующая душа гарантирована."
	_wallet.tooltip_text = _drop_info
	_show_details()

func _layout() -> void:
	if not is_instance_valid(_body):
		return
	var portrait: bool = size.x < 760
	var short_portrait: bool = portrait and size.y < 620
	_toolbar.visible = size.y >= 300

	_heading.visible = size.x >= 380
	map.custom_minimum_size.y = 60 if size.y < 300 else 130
	_detail_toggle.visible = short_portrait
	_detail_toggle.text = "Карта" if _details_only else "Описание"
	_map_frame.visible = not short_portrait or not _details_only
	_sidebar.visible = not short_portrait or _details_only
	_body.vertical = portrait
	_sidebar.custom_minimum_size = Vector2(0, 185 if size.y < 650 else 230) if portrait else Vector2(310, 0)
	if short_portrait:
		_sidebar.custom_minimum_size.y = 60 if size.y < 300 else 100
	_sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL
	_sidebar.size_flags_vertical = Control.SIZE_FILL if portrait and not short_portrait else Control.SIZE_EXPAND_FILL
	_hint.visible = size.y > 440
	_wallet.add_theme_font_size_override("font_size", 13 if size.x < 460 else 17)
	_picker.custom_minimum_size.x = 135 if portrait else 220
	_picker.add_theme_font_size_override("font_size", 13 if size.x < 460 else 17)
	_layout_navigation()
	_refresh_focus_paths.call_deferred()

func _layout_navigation() -> void:
	if not is_instance_valid(_navigation):
		return
	_fit_button.text = "Всё" if _map_frame.size.x < 460 else "Всё дерево"
	var row_width: float = _zoom_controls.get_combined_minimum_size().x + _camera_actions.get_combined_minimum_size().x + float(_navigation.get_theme_constant("separation"))
	_navigation.vertical = _map_frame.size.x < row_width + 24.0

func _zoom_slider_input(event: InputEvent) -> void:
	var direction: float = 0.0
	var amount: float = 1.0
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: direction = -1.0
			KEY_RIGHT: direction = 1.0
			_: return
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_RIGHT: direction = 1.0
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT: direction = -1.0
			_: return
		amount = absf(event.factor) if event.factor != 0.0 else 1.0
	else:
		return
	# Consume this event before HSlider can apply a second, built-in step.
	_zoom_slider.accept_event()
	if is_finite(amount):
		_zoom_slider.value = clampf(_zoom_slider.value + direction * 0.01 * amount, 0.0, 1.0)

func _zoom_slider_changed(value: float) -> void:
	var target_zoom: float = exp(lerpf(log(SkillMap.MIN_ZOOM), log(SkillMap.MAX_ZOOM), value))
	map.set_zoom(target_zoom, Vector2(-1, -1), false)

func _camera_changed(value: float) -> void:
	if is_instance_valid(_zoom):
		_zoom.text = "%.1f%%" % (value * 100.0)
	if is_instance_valid(_zoom_slider):
		var shown_zoom: float = clampf(value, SkillMap.MIN_ZOOM, SkillMap.MAX_ZOOM)
		var normalized_zoom: float = (log(shown_zoom) - log(SkillMap.MIN_ZOOM)) / (log(SkillMap.MAX_ZOOM) - log(SkillMap.MIN_ZOOM))
		_zoom_slider.set_value_no_signal(normalized_zoom)

func _toggle_details() -> void:
	_details_only = not _details_only
	_layout()

func _refresh() -> void:
	var learned: int = 0
	for node in _nodes:
		if bool(node.get("learned", false)):
			learned += 1
	_wallet.text = "Души: %d" % _souls
	_wallet.tooltip_text = "Души и навыки действуют только в текущем забеге. Печати Владыки сохраняются отдельно."
	_hint.text = "%d / %d изучено · до конца забега · %s" % [learned, _nodes.size(), "покупка один раз за души" if _can_purchase else "просмотр; покупки между волнами"]
	if _phase == "raid":
		_hint.text += " · бой на паузе"
	map.configure(_nodes, selected_id)
	_search_changed(_search.text)
	_show_details()

func _select(id: String) -> void:
	selected_id = id
	_details_only = true
	_layout()
	_show_details()

func _show_details() -> void:
	_refresh_focus_paths.call_deferred()
	for child in _requires.get_children():
		_requires.remove_child(child)
		child.queue_free()
	_detail_scroll.scroll_vertical = 0
	if selected_id == "root" or not _by_id.has(selected_id):
		_category.text = "ОБЩЕЕ ДЕРЕВО"
		_title.text = "Владыка подземелья"
		_description.text = "Шесть направлений можно развивать параллельно. Выберите круглый узел, чтобы увидеть его эффект и цену.\n\nПеретаскивайте карту мышью или пальцем. Колесо, ползунок и жест двумя пальцами меняют масштаб. Мини-карта возвращает к нужному участку.\n\nКаждый навык покупается один раз. Души и изученные навыки сбросятся после забега."
		if not _drop_info.is_empty():
			_description.text += "\n\n" + _drop_info
		_buy.text = "Выберите навык на карте"
		_buy.disabled = true
		return
	var node: Dictionary = _by_id[selected_id]
	_category.text = str(CATEGORY_NAMES.get(str(node.get("category", "shared")), "Общие навыки")).to_upper() + " · %d душ" % int(node.get("cost", 0))
	_title.text = str(node.get("name", selected_id))
	_description.text = str(node.get("description", node.get("effect", "")))
	var parents: Array = node.get("parents", [])
	if parents.is_empty():
		parents.append_array(node.get("requires_all", []))
		parents.append_array(node.get("requires_any", []))
	var actual_parents: Array = parents.filter(func(id): return str(id) != "root")
	if not actual_parents.is_empty():
		_requires.add_child(_label("Нужен любой из:" if str(node.get("mode", "all")) == "any" else "Нужны все:" if actual_parents.size() > 1 else "После навыка:", 12, MUTED))
		for parent_id in actual_parents:
			var parent: Dictionary = _by_id.get(str(parent_id), {})
			var learned: bool = bool(parent.get("learned", false))
			var button: Button = _button(("✓ " if learned else "○ ") + str(parent.get("name", parent_id)), _focus.bind(str(parent_id)))
			button.add_theme_color_override("font_color", GREEN if learned else MUTED)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_requires.add_child(button)
	var required_lord: String = str(node.get("required_lord", ""))
	if not required_lord.is_empty():
		var names := {"fallen_knight": "Падший рыцарь", "necromancer": "Некромант", "plague_alchemist": "Чумной алхимик"}
		_requires.add_child(_label("Владыка: " + str(names.get(required_lord, required_lord)), 12, GOLD))
	var learned: bool = bool(node.get("learned", false))
	var available: bool = bool(node.get("available", node.get("can_buy", false)))
	_buy.disabled = learned or not available or not _can_purchase
	if learned:
		_buy.text = "Изучено · до конца забега"
	elif not _can_purchase:
		_buy.text = "Покупки между волнами"
	elif available:
		_buy.text = "Изучить · %d душ" % int(node.cost)
	else:
		_buy.text = str(node.get("reason", "Условия не выполнены"))
	_buy.tooltip_text = str(node.get("reason", ""))

func _focus(id: String) -> void:
	map.set_selection(id, true)
	_select(id)

func _search_changed(query: String) -> void:
	map.set_search(query)
	_picker.clear()
	var text: String = query.strip_edges().to_lower()
	for node in _nodes:
		if not text.is_empty() and not str(node.name).to_lower().contains(text):
			continue
		var index: int = _picker.item_count
		_picker.add_item(str(node.name))
		_picker.set_item_metadata(index, str(node.id))
	_picker.disabled = _picker.item_count == 0
	if _picker.item_count > 0:
		_picker.select(-1)
		_picker.text = "Найдено: %d" % _picker.item_count
	else:
		_picker.text = "Нет совпадений"

func _pick_result(index: int) -> void:
	if index >= 0 and index < _picker.item_count:
		_focus(str(_picker.get_item_metadata(index)))

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	return button

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _collect_focus_controls(node: Node, result: Array[Control]) -> void:
	if node is Control:
		if not node.is_visible_in_tree():
			return
		if node.focus_mode == Control.FOCUS_ALL and not (node is BaseButton and node.disabled):
			result.append(node)
	for child in node.get_children():
		_collect_focus_controls(child, result)


func _refresh_focus_paths() -> void:
	if not is_inside_tree():
		return
	var controls: Array[Control] = []
	_collect_focus_controls(self, controls)
	for index in range(controls.size()):
		var control: Control = controls[index]
		var previous: NodePath = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
		var following: NodePath = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = following
		control.focus_neighbor_left = NodePath(".") if control == _zoom_slider else previous
		control.focus_neighbor_top = previous
		control.focus_neighbor_right = NodePath(".") if control == _zoom_slider else following
		control.focus_neighbor_bottom = following


func focus_default() -> void:
	_refresh_focus_paths()
	if map.is_visible_in_tree():
		map.grab_focus()
	else:
		cycle_focus(false)


func cycle_focus(backward: bool) -> void:
	var controls: Array[Control] = []
	_collect_focus_controls(self, controls)
	if controls.is_empty():
		return
	var index: int = controls.find(get_viewport().gui_get_focus_owner())
	if index < 0:
		index = controls.size() if backward else -1
	index = (index + (-1 if backward else 1) + controls.size()) % controls.size()
	controls[index].grab_focus()
