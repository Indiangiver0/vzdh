extends RefCounted
## Presentation text only. No profile access, model dependencies or numeric rules.
## Exact phrases and a finite set of anchored printf templates; unknown text is kept.

const SkillEnglish = preload("res://scripts/run_skill_english.gd")
const MoreEnglish = preload("res://scripts/game_language_more.gd")
const RoomEnglish = preload("res://scripts/game_language_rooms.gd")

static var _locale: String = "ru"
static var _ready_catalog: bool = false
static var _phrases: Dictionary = {}
static var _rules: Array[Dictionary] = []


static func set_locale(value: String) -> void:
	_locale = "en" if value.strip_edges().to_lower() == "en" else "ru"


static func get_locale() -> String:
	return _locale


static func is_english() -> bool:
	return _locale == "en"


static func text(value: String) -> String:
	if not is_english() or value.is_empty():
		return value
	_prepare_catalog()
	return _translate(value, 0)


static func format_text(template: String, args: Array) -> String:
	# Callers translate any textual arguments explicitly; numbers and IDs stay intact.
	return text(template) % args


static func skill_name(id: String, fallback: String) -> String:
	return str(SkillEnglish.ENTRIES[id][0]) if is_english() and SkillEnglish.ENTRIES.has(id) else text(fallback)


static func skill_description(id: String, fallback: String) -> String:
	return str(SkillEnglish.ENTRIES[id][1]) if is_english() and SkillEnglish.ENTRIES.has(id) else text(fallback)


static func _translate(value: String, depth: int) -> String:
	if _phrases.has(value):
		return str(_phrases[value])
	if depth >= 4:
		return value
	for rule in _rules:
		if not value.begins_with(str(rule.prefix)):
			continue
		var found: RegExMatch = rule.regex.search(value)
		if found == null:
			continue
		var arguments: Array = []
		for index in range(rule.strings.size()):
			var captured: String = found.get_string(index + 1)
			arguments.append(_translate(captured, depth + 1) if rule.strings[index] else captured)
		return str(rule.output) % arguments
	# Tooltips join complete independently translatable lines. Never split into words.
	if value.contains("\n"):
		var lines: PackedStringArray = value.split("\n")
		for index in range(lines.size()):
			lines[index] = _translate(lines[index], depth + 1)
		return "\n".join(lines)
	# Fragments are glued into longer lines at runtime: translate each complete piece.
	if depth < 4 and _has_cyrillic(value):
		var trimmed: String = value.strip_edges()
		if trimmed != value and not trimmed.is_empty():
			var start: int = value.find(trimmed)
			return value.substr(0, start) + _translate(trimmed, depth + 1) + value.substr(start + trimmed.length())
		for marker in ["+ ", "- ", "* "]:
			if value.begins_with(marker):
				return marker + _translate(value.substr(marker.length()), depth + 1)
		for separator in [" · ", ". "]:
			if value.contains(separator):
				var pieces: PackedStringArray = value.split(separator)
				for index in range(pieces.size()):
					var closed: bool = separator == ". " and index < pieces.size() - 1
					var piece: String = _translate(pieces[index] + ("." if closed else ""), depth + 1)
					pieces[index] = piece.trim_suffix(".") if closed else piece
				return separator.join(pieces)
	return value


static func _has_cyrillic(value: String) -> bool:
	for character in value:
		var code: int = character.unicode_at(0)
		if code >= 0x0400 and code <= 0x04FF:
			return true
	return false


static func _prepare_catalog() -> void:
	if _ready_catalog:
		return
	_ready_catalog = true
	for catalog in [UI, TEMPLATES, CONTENT, ERRORS, MoreEnglish.ENTRIES, RoomEnglish.ENTRIES]:
		for source in catalog:
			var translated: String = str(catalog[source])
			_phrases[str(source)] = translated
			_phrases[_display_alias(str(source))] = _display_alias(translated)
			if not str(source).contains("%"):
				_phrases[str(source).to_upper()] = translated.to_upper()
				_phrases[_display_alias(str(source)).to_upper()] = _display_alias(translated).to_upper()
	# Rules quote skill names by their Russian catalog name, for example "Learn first: %s."
	var skills: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/run_skills.json"))
	if skills is Dictionary:
		for skill: Variant in skills.get("skills", []):
			var id: String = str(skill.get("id", ""))
			if SkillEnglish.ENTRIES.has(id) and not _phrases.has(str(skill.get("name", ""))):
				_phrases[str(skill.get("name", ""))] = str(SkillEnglish.ENTRIES[id][0])
	var tokens := RegEx.new()
	tokens.compile("%(?:\\.[0-9]+)?[dfs]|%%")
	for source in _phrases:
		var matches: Array[RegExMatch] = tokens.search_all(str(source))
		if matches.is_empty():
			continue
		var pattern: String = "\\A"
		var last: int = 0
		var strings: Array[bool] = []
		var prefix: String = ""
		for token in matches:
			pattern += _escape_regex(str(source).substr(last, token.get_start() - last))
			var specifier: String = token.get_string()
			if specifier == "%%":
				pattern += "%"
			else:
				if strings.is_empty():
					prefix = str(source).substr(0, token.get_start()).replace("%%", "%")
				strings.append(specifier.ends_with("s"))
				pattern += "(.*?)" if specifier.ends_with("s") else "([+-]?[0-9]+(?:\\.[0-9]+)?)" if specifier.ends_with("f") else "([+-]?[0-9]+)"
			last = token.get_end()
		if strings.is_empty():
			continue
		pattern += _escape_regex(str(source).substr(last)) + "\\z"
		var regex := RegEx.new()
		if regex.compile("(?s)" + pattern) != OK:
			continue
		var translated: String = str(_phrases[source])
		var output: String = ""
		last = 0
		for token in tokens.search_all(translated):
			output += translated.substr(last, token.get_start() - last).replace("%", "%%")
			output += "%%" if token.get_string() == "%%" else "%s"
			last = token.get_end()
		output += translated.substr(last).replace("%", "%%")
		_rules.append({"regex": regex, "prefix": prefix, "output": output, "strings": strings, "weight": str(source).length()})
	# "%s потерял добычу: возвращено %d" must win over the looser "%s: возвращено %d".
	_rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.weight) > int(b.weight))


static func _escape_regex(value: String) -> String:
	var escaped: String = ""
	for character in value:
		if "\\.^$|?*+()[]{}".contains(character):
			escaped += "\\"
		escaped += character
	return escaped


static func _display_alias(value: String) -> String:
	# Finite aliases mirror main._ui_text sanitizing. Never rewrite the input itself.
	for pair in [["→", ">"], ["←", "<"], ["↔", "<>"], ["↗", ""], ["▸", "+"], ["▾", "-"], ["◇", ""], ["✓", "*"], ["×", "x"], ["−", "-"], ["≤", "<="], ["≥", ">="], ["\ufe0f", ""], ["\ufe0e", ""], ["\u200b", ""]]:
		value = value.replace(pair[0], pair[1])
	return value


const UI: Dictionary = {
	"Выберите язык / Choose language": "Выберите язык / Choose language",
	"Изменить язык можно в настройках. / You can change the language in Settings.": "Изменить язык можно в настройках. / You can change the language in Settings.",
	"Русский": "Русский",
	"English": "English",
	"Язык": "Language",
	"Далее": "Next",
	"Настройки": "Settings",
	"Полный экран / окно · F11": "Fullscreen / window · F11",
	"Звук: включён": "Sound: on",
	"Звук: выключен": "Sound: off",
	"Громкость": "Volume",
	"Скорость просмотра рейда": "Raid speed",
	"Меню": "Menu",
	"Главное меню": "Main menu",
	"Новое подземелье": "New dungeon",
	"Начать новый забег": "Start new run",
	"Начать новое подземелье?": "Start a new dungeon?",
	"Назад к подземелью": "Return to dungeon",
	"Ваш трон.\nИх последний рейд.": "Your throne.\nTheir final raid.",
	"ВАШ ТРОН.\nВАШЕ ПОДЗЕМЕЛЬЕ.\nИХ ПОСЛЕДНИЙ РЕЙД.": "YOUR THRONE.\nYOUR DUNGEON.\nTHEIR FINAL RAID.",
	"Стройте глубже. Командуйте защитой.\nВмешивайтесь в бой силой своего Лорда.": "Build deeper. Command your defenses.\nTurn the tide with your Lord's power.",
	"Стройте защиту. В бой вступайте силой Лорда.": "Build your defenses. Join the battle with your Lord's power.",
	"Стройте лабиринт, защищайте казну и открывайте новые слои глубины.": "Build a labyrinth, defend your treasury and unlock deeper layers.",
	"Ваш следующий правитель": "Your next ruler",
	"Научиться играя": "Learn by playing",
	"Обучение · сыграть с подсказками": "Tutorial · play with guidance",
	"Пропустить обучение": "Skip tutorial",
	"Повторить обучение": "Retry tutorial",
	"Начать обучение": "Start tutorial",
	"Начать учебное подземелье?": "Start a tutorial dungeon?",
	"Начать обычную игру": "Start a normal game",
	"Пройти обучение в игре": "Play the tutorial",
	"Мой забег": "My run",
	"УЧИМСЯ · ": "LEARNING · ",
	"ОБУЧЕНИЕ  ·  ": "TUTORIAL  ·  ",
	"Пропуск": "Skip",
	"Пропустить": "Skip",
	"Попробуем ещё раз?": "Try again?",
	"Учебный забег не меняет рекорды, Печати и постоянные открытия.": "Tutorial runs do not affect records, Seals or permanent unlocks.",
	"Сейчас выполните подсвеченный шаг. «Пропустить» начинает обычную игру.": "Complete the highlighted step. Choose Skip to start a normal game.",
	"Подсказка": "Hint",
	"Коллекция": "Collection",
	"Как играть": "How to play",
	"Выйти из игры": "Quit game",
	"Назад": "Back",
	"Продолжить": "Continue",
	"Пауза": "Pause",
	"Отмена": "Cancel",
	"Снять выбор": "Clear selection",
	"Выбрать": "Select",
	"Выбрано": "Selected",
	"Получено": "Acquired",
	"Открыто": "Unlocked",
	"Магазин": "Shop",
	"Отряд": "Party",
	"Карта": "Map",
	"Описание": "Details",
	"Сведения": "Details",
	"Навыки": "Skills",
	"Навыки забега": "Run skills",
	"Навыки этого забега": "Skills from this run",
	"Лорд": "Lord",
	"Лорды": "Lords",
	"Лорды подземелья": "Dungeon Lords",
	"Лорд Подземелья": "Dungeon Lord",
	"Владыка подземелья": "Dungeon Lord",
	"Золото": "Gold",
	"зол.": "gold",
	"бесплатно": "free",
	"Души": "Souls",
	"Печати": "Seals",
	"Печати Владыки": "Lord's Seals",
	"Волна": "Wave",
	"Рекорд": "Record",
	"Подземелье": "Dungeon",
	"Подземелье · свободная сетка": "Dungeon · free grid",
	"Карта подземелья": "Dungeon map",
	"Вся карта": "Whole map",
	"К отряду": "Follow party",
	"Масштаб −": "Zoom out",
	"Масштаб +": "Zoom in",
	"Открывает следующий слой. Раскопка клеток оплачивается отдельно.": "Unlocks the next layer. Digging cells costs extra.",
	"Открыть следующий слой для раскопок. Новые клетки оплачиваются отдельно.": "Unlock the next layer for excavation. New cells cost extra.",
	"+ — раскопать. Маркер между комнатами меняет проход. Удерживайте комнату и тяните для переноса; пустое поле — для движения карты.": "+ digs a cell. Tap a marker between rooms to change a passage. Hold and drag a room to move it; drag empty space to pan.",
	"+ — раскопать · маркер — проход/стена · удержание и движение — перенос": "+ dig · marker: passage/wall · hold and drag: move",
	"+ — раскопать · маркер — проход/стена · ЛКМ — перенос · ПКМ/СКМ — карта": "+ dig · marker: passage/wall · left drag: move · right/middle drag: pan",
	"Сделка: выберите пустое место.": "Deal: choose an empty space.",
	"Сделка: выберите пустое место. Отмена — Esc или «Снять выбор».": "Deal: choose an empty space. Cancel with Esc or Clear selection.",
	"«Сведения» — улучшение комнаты. Другое место — перенос.": "Details upgrades the room. Choose another space to move it.",
	"Выберите другое место для переноса.": "Choose another space to move the room.",
	"Скорость следующего и текущего боя: ×1 / ×2 / ×4": "Speed for the current and next battle: ×1 / ×2 / ×4",
	"Герои у трона — скорость ×1. Её можно изменить вручную.": "Heroes reached the throne: speed is now ×1. You can change it manually.",
	"Пять героев. Перед началом подготовьте защиту и проверьте запас золота.": "Five heroes. Prepare your defenses and check your gold before starting.",
	"Защита действует автоматически": "Defenses fight automatically",
	"Пробел — пауза · E — сорвать привал": "Space: pause · E: interrupt camp",
	"Пробел — пауза · Q — сила Лорда": "Space: pause · Q: Lord's power",
	"Герои отдыхают. Пауза останавливает привал; E срывает его за золото.": "Heroes are resting. Pause stops the camp timer; E interrupts camp for gold.",
	"Группа спускается в подземелье.": "The party descends into the dungeon.",
	"До следующей порции лечения": "Time until the next healing pulse",
	"E — срыв привала · Q недоступна": "E: interrupt camp · Q unavailable",
	"E отменит оставшееся лечение; доступна на паузе. Q недоступна.": "E cancels the remaining healing, even while paused. Q is unavailable.",
	"Привал сорван.": "Camp interrupted.",
	"Сила Лорда применена.": "Lord's power used.",
	"Разведка": "Scouting",
	"Приключенцы": "Adventurers",
	"Следующая группа": "Next party",
	"Группа в подземелье": "Party in the dungeon",
	"Оружие": "Weapon",
	"Защита": "Defense",
	"Пустой слот": "Empty slot",
	"Временно отключено": "Temporarily disabled",
	"Временно отключено эффектом комнаты": "Temporarily disabled by a room effect",
	"Оружие подменено мимиком до конца волны": "Weapon replaced by a mimic until the wave ends",
	"У трона действует один самый сильный страж": "Only the strongest guardian assists at the throne",
	"Ранги 2 / 5 / 15": "Ranks 2 / 5 / 15",
	"Посмотреть путь и будущие развилки": "View this path and its future branches",
	"Улучшить · выбор без доплаты": "Upgrade · choose at no extra cost",
	"Максимальный ранг": "Maximum rank",
	"Продолжить уже доступный выбор. Золото не списывается.": "Complete the pending choice. No gold is spent.",
	"Повысить ранг. Доступный выбор усиления откроется сразу.": "Increase rank. Any available upgrade choice opens immediately.",
	"Раскуплено": "Sold out",
	"Вход остаётся на границе подземелья.": "The entrance stays at the edge of the dungeon.",
	"Выберите комнату в магазине.": "Choose a room in the shop.",
	"Награда за рубеж": "Milestone reward",
	"Новый чертёж": "New blueprint",
	"Древняя реликвия": "Ancient relic",
	"Выберите комнату для магазина этого забега. Она появится в ближайшем предложении.": "Choose a room for this run's shop. It will appear in the next offer.",
	"Выберите постоянную реликвию до конца забега или разовый бонус прямо сейчас.": "Choose a relic lasting until the end of the run or an immediate one-time bonus.",
	"Разовый бонус · сразу": "One-time bonus · immediate",
	"Пассивно · до конца забега": "Passive · until the run ends",
	"Получить сейчас": "Claim now",
	"Новая глубина": "New depth",
	"Новый этаж · новые возможности": "New floor · new opportunities",
	"Выберите свойство слоя": "Choose a layer trait",
	"Выберите свойство этажа": "Choose a floor trait",
	"Выбрать свойство слоя": "Choose a layer trait",
	"Выбрать свойство этажа": "Choose a floor trait",
	"Свойство действует на комнаты в новом слое глубины. Клетки в нём раскапываются отдельно.": "This trait affects rooms in the new depth layer. Its cells must be dug separately.",
	"Свойство влияет на пять комнат этого этажа и сохраняется до конца забега.": "This trait affects the floor's five rooms until the end of the run.",
	"Отряд отступил": "Party retreated",
	"Подземелье устояло": "Dungeon defended",
	"Отряд отступил, добыча возвращена": "Party retreated; stolen gold recovered",
	"Герои унесли добычу": "Heroes escaped with the loot",
	"Забег продолжается. Награды за защиту нет; награды за убитых героев сохранены.": "The run continues. No defense reward; rewards for slain heroes are kept.",
	"Герои стали частью вашей истории.": "The heroes have become part of your legend.",
	"Комнаты восстановлены. Планировка и оставшееся золото сохраняются.": "Rooms restored. Your layout and remaining gold are kept.",
	"Кнопка «Навыки» доступна в подготовке. Можно потратить души или сохранить их.": "Skills are available during preparation. Spend your souls or save them.",
	"Сохраняется между забегами": "Persists between runs",
	"Трон пал": "The throne has fallen",
	"Каждое подземелье\nоставляет легенду.": "Every dungeon\nleaves a legend.",
	"Лорды · открыть и улучшить": "Lords · unlock and upgrade",
	"Итоги волны": "Wave results",
	"Итоги забега": "Run results",
	"Выбрать награду": "Choose a reward",
	"Справочник": "Guide",
	"Типы угроз": "Threat types",
	"Навыки и души": "Skills and souls",
	"Способность Q": "Q ability",
	"Босс-отряд": "Boss party",
	"Привал и E": "Camp and E",
	"Управление": "Controls",
	"Улучшение комнат": "Room upgrades",
	"Защита казны": "Treasury defense",
	"Слои глубины": "Depth layers",
	"Проложите от входа к казне путь в обход трона. При первом ограблении герои заберут половину текущего золота и могут повернуть к выходу. Победите носителей, чтобы вернуть добычу.": "Give heroes a route from the entrance to the treasury that bypasses the throne. On the first robbery, they take half your current gold and may head back to the exit. Defeat the carriers to recover the loot.",
	"Кнопка «Глубже» покупает доступ к следующему слою. На телефоне она находится в окне «Карта». Выберите свойство слоя, затем раскапывайте клетки для строительства.": "Use Dig Deeper to unlock the next depth layer. On a phone, find it under Map. Choose a layer trait, then excavate cells to build there.",
	"Нажмите «Улучшить» в сведениях о комнате. Первый выбор усиления откроется сразу после прокачки; следующие - на рангах 5 и 15. На телефоне выберите комнату и нажмите «Сведения». После «Назад» тот же выбор доступен без доплаты.": "Use Upgrade in the room details. Choose the first evolution after reaching rank 2, then evolve again at ranks 5 and 15. On a phone, select the room and tap Details. You can go back and make the choice later at no extra cost.",
	"Души иногда сохраняются после гибели героев. После двух неудач следующая награда гарантирована. Кнопка «Навыки» открывает общее дерево: один узел — одна покупка за забег. Покупать можно в подготовке; в бою и на привале карта ставит игру на паузу, закрытие возвращает прежнюю паузу. Души и дерево сбрасываются после забега, Печати Владыки сохраняются.": "Defeated heroes can leave souls. After two misses the next drop is guaranteed. Skills opens the shared tree, where each node can be bought once per run during preparation. Opening the tree during combat or a camp pauses the game. Closing it restores the previous pause state. Souls and skills reset at the end of the run. Lord's Seals carry over.",
	"Два заряда на волну. Каждое применение стоит половину базового дохода этой волны, без бонусов заработка. Цена видна заранее и не меняется в бою; неудачное нажатие ничего не списывает.": "Two charges per wave. Each cast costs half the wave's base income before skill discounts. Income bonuses do not raise the cost. The price is visible in advance and stays fixed in combat. Failed casts cost nothing.",
	"На развилках и в безопасных местах при тяжёлом ранении одного героя отряд может отдыхать. Один привал на место за волну. Таймер, оставшиеся порции и возможное лечение показаны у кнопки E. Пауза, меню и окна останавливают отдых. E за золото отменяет оставшееся лечение текущего привала и работает на паузе. Лимита зарядов нет: первое успешное применение за волну бесплатно, второе стоит 25% базового дохода, следующие — 50%. Неудача ничего не списывает. Q на привале недоступна.": "The party may camp at junctions or in safe cells when a hero is badly wounded. Each spot can host one camp per wave. The E control shows time and healing remaining. Pausing or opening a menu stops the timer. E ends the camp and cancels future healing, even while paused. The first interruption per wave is free, the second costs 25% of base wave income and later ones cost 50%. Failed attempts cost nothing. Q is unavailable during camps.",
	"Магазин > пустое место. Клик выбирает комнату. Для переноса или обмена комнаты, казны и трона потяните их ЛКМ; пальцем сначала удержите. ПКМ/СКМ двигают карту. Пробел — пауза, Q — сила Лорда, E — сорвать привал. Esc отменяет жест, затем выбор, затем открывает меню. F11 — полный экран.": "Choose a room in Shop, then an empty cell. Click a room to select it. Drag with the left mouse button to move or swap a room, treasury or throne. On touch, hold before dragging. Pan with the right or middle mouse button. Space pauses, Q casts the Lord's power and E interrupts a camp. Esc cancels the gesture or selection, then opens the menu. F11 toggles fullscreen.",
	"Корона переходит к следующему": "The crown passes to the next",
	"Печати выдаются за волны, поверженных героев, особые отряды и новые рубежи. Их можно потратить на открытие Лордов или мастерство.": "Earn Seals from waves, slain heroes, special parties and new milestones. Spend them to unlock Lords or improve mastery.",
	"Выбор Лорда, мастерство и вариант способности применяются в новом забеге.": "Your Lord, mastery and ability variant apply to the next run.",
	"Два заряда на волну": "Two charges per wave",
	"Выбран для нового забега": "Selected for the next run",
	"Выбрать Лорда": "Select Lord",
	"Посмотреть дерево мастерства": "View mastery tree",
	"Сохраняется между забегами. Второй вариант силы — на мастерстве 3.": "Persists between runs. The second ability variant unlocks at mastery 3.",
	"Сменить бесплатно": "Switch for free",
	"Откройте Лорда": "Unlock the Lord",
	"Мастерство Лорда": "Lord mastery",
	"Выбрать бесплатно": "Select for free",
	"Мастерство полностью развито": "Mastery fully upgraded",
	"Выбранная сила и мастерство применятся в новом забеге.": "Your chosen power and mastery apply to the next run.",
	"Лорд выбран. Новый правитель вступит в бой в следующем забеге.": "Lord selected. The new ruler will fight in your next run.",
	"Вариант способности выбран для следующего забега.": "Ability variant selected for the next run.",
	"Постоянные открытия": "Permanent unlocks",
	"Реликвии забега": "Run relics",
	"Комната · до конца забега": "Room · until the run ends",
	"Выберите доступный узел": "Choose an available node",
	"Считаются разные типы на поле, а не количество копий.": "Counts distinct room types on the map, not the number of copies.",
	"Выберите свободное место для комнаты по сделке.": "Choose an empty space for the deal room.",
	"Размещение сделки отменено.": "Deal placement cancelled.",
	"Лаборатория продлевает яд. Мастерская усиливает ловушки.": "The Laboratory extends poison. The Workshop strengthens traps.",
	"Существа": "Creatures",
	"Ловушки": "Traps",
	"Яды": "Poisons",
	"Экономика": "Economy",
	"Ритуалы Q": "Q rituals",
	"Общие навыки": "Shared skills",
	"Найти навык…": "Find a skill…",
	"Отдалить карту": "Zoom out",
	"Приблизить карту": "Zoom in",
	"Масштаб карты: перетащите ползунок или нажмите ← / →": "Map zoom: drag the slider or press ← / →",
	"Центр": "Center",
	"Всё дерево": "Whole tree",
	"Всё": "All",
	"Показать всё дерево": "Show the whole tree",
	"Выберите навык": "Select a skill",
	"Выберите навык на карте": "Select a skill on the map",
	"Души и навыки действуют только в текущем забеге. Печати Владыки сохраняются отдельно.": "Souls and skills last for the current run only. Lord's Seals are saved separately.",
	"покупка один раз за души": "buy once with souls",
	"просмотр; покупки между волнами": "view only; purchase between waves",
	"бой на паузе": "combat paused",
	"Общее дерево": "Shared skill tree",
	"Шесть направлений можно развивать параллельно. Выберите круглый узел, чтобы увидеть его эффект и цену.\n\nПеретаскивайте карту мышью или пальцем. Колесо, ползунок и жест двумя пальцами меняют масштаб. Мини-карта возвращает к нужному участку.\n\nКаждый навык покупается один раз. Души и изученные навыки сбросятся после забега.": "Develop six paths in parallel. Select a round node to see its effect and price.\n\nDrag the map with a mouse or finger. Use the wheel, slider or a two-finger gesture to zoom. Use the minimap to navigate.\n\nEach skill can be purchased once. Souls and learned skills reset after the run.",
	"Нужен любой из:": "Requires any of:",
	"Нужны все:": "Requires all:",
	"После навыка:": "After skill:",
	"Изучено · до конца забега": "Learned · until the run ends",
	"Покупки между волнами": "Purchase between waves",
	"Условия не выполнены": "Requirements not met",
	"Нет совпадений": "No matches",
	"Следующая душа гарантирована.": "The next soul is guaranteed.",
	"Возвращаются к выходу": "Returning to the exit",
	"Исследуют подземелье": "Exploring the dungeon",
	"Зажмите комнату — перенос / обмен · колесо — масштаб": "Hold a room: move / swap · wheel: zoom",
	"Зажмите комнату — перенос · щипок — масштаб": "Hold a room: move · pinch: zoom",
	"Следуйте подсветке · щипок — масштаб": "Follow the highlights · pinch: zoom",
	"Следуйте подсветке · колесо — масштаб": "Follow the highlights · wheel: zoom",
	"Вход / выход": "Entrance / exit",
	"Казна": "Treasury",
	"Трон": "Throne",
	"Пасть": "Maw",
	"Свободно": "Empty",
	"Разместить": "Place",
	"Обезврежена": "Disarmed",
	"Вампир улетел": "Vampire retreated",
	"Нажмите границу, чтобы открыть проход или возвести стену.": "Tap a boundary to open a passage or build a wall.",
	"Казна: при первом ограблении герои забирают половину текущего золота. Добычу можно отбить на обратном пути.": "Treasury: the first robbery takes half your current gold. Recover the loot on the heroes' return journey.",
	"Трон Лорда. Его гибель завершает забег.": "The Lord's throne. The Lord's death ends the run.",
	"Вход героев и выход с добычей.": "Where heroes enter and escape with loot.",
	"Пустая клетка. Выберите комнату в магазине или перенесите сюда существующую.": "Empty cell. Choose a room in the shop or move an existing one here.",
	"Выберите клетку": "Choose a cell",
	"Отмена переноса": "Cancel move",
	"Перенести": "Move",
	"Поменять местами": "Swap",
	"Сердце": "Heart",
	"ПАСТЬ · общий бой": "MAW · shared combat",
	"Сердце уничтожено": "Heart destroyed",
	"Готов помочь": "Ready to assist",
	"Пробуждение": "Awakening",
	"К гробу": "To the coffin",
	"Подкрепление": "Reinforcement",
	"Повержен": "Slain",
	"Силен против телесных · слаб против духов": "Strong against corporeal creatures · weak against spirits",
	"Лечение · защита группы от яда -25%": "Healing · party poison damage taken -25%",
	"Лечение и защита от яда заглушены": "Healing and poison protection silenced",
	"Магия особенно опасна духам · заряжает заклинание": "Magic is especially dangerous to spirits · charging a spell",
	"Магия заглушена": "Magic silenced",
	"Силен против телесных · духи почти неуязвимы к топору": "Strong against corporeal creatures · spirits resist the axe",
	"ЯРОСТЬ +25%": "RAGE +25%",
	"Ярость при HP <= 40%": "Rage at HP <= 40%",
	"Песня: +15% урона всему отряду": "Song: +15% damage for the entire party",
	"Песня заглушена": "Song silenced",
	"Коррозия: −1 брони": "Corrosion: −1 armor",
	"Тяжёлое дыхание: −10% обычного удара": "Labored breathing: −10% normal attack damage",
	"Метка засады": "Ambush mark",
	"В коконе": "Cocooned",
	"Отходит под прикрытием": "Retreating under cover",
	"Вытащен вперёд": "Pulled to the front",
	"Под гипнозом": "Hypnotized",
	"Оружие подменено": "Weapon replaced",
	"Спора": "Spore",
}

const TEMPLATES: Dictionary = {
	"Волна %d  ·  %d зол.": "Wave %d  ·  %d gold",
	"Лорд %d/%d HP": "Lord %d/%d HP",
	"Навыки\n%d": "Skills\n%d",
	"Навыки · душ: %d": "Skills · souls: %d",
	"Навыки · %d": "Skills · %d",
	"Начать волну %d": "Start wave %d",
	"НАЧАТЬ ВОЛНУ %d": "START WAVE %d",
	"Глубже · %d зол.": "Dig deeper · %d gold",
	"Лечить Лорда · %d зол.": "Heal Lord · %d gold",
	"Восстановит %d HP.": "Restores %d HP.",
	"Восстановит %d HP. Придворный лекарь: экономия %d зол.": "Restores %d HP. Court Healer: saves %d gold.",
	"Q · %s\n%d/%d · %d зол.": "Q · %s\n%d/%d · %d gold",
	"Q · %s · %d/%d · %d зол.": "Q · %s · %d/%d · %d gold",
	"%s · %d/%d · %d зол.": "%s · %d/%d · %d gold",
	"E · Сорвать привал · %s": "E · Interrupt camp · %s",
	"%d зол.": "%d gold",
	"%d душ": "%d souls",
	"%d душа": "%d soul",
	"%d души": "%d souls",
	"%d печатей": "%d Seals",
	"Привал · %.1f с · порций: %d · до %d HP": "Camp · %.1f s · pulses: %d · up to %d HP",
	"Привал · ещё %.1f с из %d": "Camp · %.1f s left of %d",
	"Осталось порций: %d · ещё до %d HP отряду": "Pulses left: %d · up to %d more party HP",
	"Отменить ещё до %d HP лечения за %d зол. Уже полученные HP остаются. Доступна на паузе.\n%s": "Cancel up to %d more HP of healing for %d gold. HP already restored is kept. Available while paused.\n%s",
	"Привал · %.1f с · ещё до %d HP · подробнее в «Отряд»": "Camp · %.1f s · up to %d more HP · see Party for details",
	"Привал: ещё до %d HP · сила лечения %d%%": "Camp: up to %d more HP · healing strength %d%%",
	"БОСС-ВОЛНА! · %d · Клятва пяти": "BOSS WAVE! · %d · Oath of Five",
	"Цена: %d зол. · зафиксирована на волну, без бонусов дохода": "Cost: %d gold · fixed for this wave, without income bonuses",
	"%s · отряд: %d": "%s · party: %d",
	"Следующая группа · %d чел.": "Next party · heroes: %d",
	"Группа в подземелье · %d чел.": "Party in the dungeon · heroes: %d",
	"Уровень %d": "Level %d",
	"%d/%d HP    Урон %d  ·  Броня %d": "%d/%d HP    Damage %d  ·  Armor %d",
	"Уровень %d · мастерство %d / 5": "Level %d · mastery %d / 5",
	"%d/%d HP · Урон %d · Броня %d": "%d/%d HP · Damage %d · Armor %d",
	"Опыт Лорда: %d / %d": "Lord XP: %d / %d",
	"Q: %d зол. за применение": "Q: %d gold per use",
	"%d клеток": "%d cells",
	"%s · нажмите пустую клетку": "%s · tap an empty cell",
	"Подземелье · %d этаж.": "Dungeon · %d floors",
	"%d этаж. / %d мест": "%d floors / %d spaces",
	"Этажей: %d": "Floors: %d",
	"Разместить: %s. Выберите пустую комнату.": "Place: %s. Choose an empty room.",
	"+ Этаж · %d зол.": "+ Floor · %d gold",
	"+ УГЛУБИТЬ ПОДЗЕМЕЛЬЕ · %d зол.": "+ DEEPEN DUNGEON · %d gold",
	"Строительная смета: экономия %d зол.": "Construction Estimate: saves %d gold",
	"HP %d · Урон %d · Броня %d": "HP %d · Damage %d · Armor %d",
	"Яд %.2f за тик · %d тиков": "Poison %.2f per tick · %d ticks",
	"Действует %d т. · Урон %d": "Lasts %d ticks · Damage %d",
	"Урон %d": "Damage %d",
	"Следующий выбор: ранг %d": "Next choice: rank %d",
	"Улучшить · %d зол.": "Upgrade · %d gold",
	"Скидки навыков: −%d зол.": "Skill discounts: −%d gold",
	"Продать · +%d зол.": "Sell · +%d gold",
	"%s: −%d зол.": "%s: −%d gold",
	"Скидка навыков: %d зол.": "Skill discount: %d gold",
	"%d зол. · %d шт.": "%d gold · %d in stock",
	"%d зол. · %d шт. · мало золота": "%d gold · %d in stock · not enough gold",
	"Подготовка · Q: %d зол. за применение": "Preparation · Q: %d gold per use",
	"%s Повторяется при каждом проходе. Следопыт: одна попытка за волну, 50% полностью отключить; при провале полный эффект. Арсенал расходует запас болтов.": "%s Triggers on every passage. Ranger: one attempt per wave, 50% chance to disable completely; on failure, the full effect applies. The Arsenal consumes its bolt supply.",
	"Казна · удержите и потяните для переноса или обмена.": "Treasury · hold and drag to move or swap.",
	"Трон · удержите и потяните для переноса или обмена.": "Throne · hold and drag to move or swap.",
	"Казна · перетащите ЛКМ для переноса или обмена.": "Treasury · left-drag to move or swap.",
	"Трон · перетащите ЛКМ для переноса или обмена.": "Throne · left-drag to move or swap.",
	"Волна %d отражена": "Wave %d defended",
	"Украдено: %d · Возвращено: %d · Унесено: %d": "Stolen: %d · Recovered: %d · Escaped: %d",
	"Убито: %d   ·   Золото: +%d   ·   XP: +%d": "Kills: %d   ·   Gold: +%d   ·   XP: +%d",
	"Здоровье Лорда: %d / %d": "Lord HP: %d / %d",
	"Урон Лорду: %d HP\nГерои получили: %d уровней и %d предметов": "Damage to Lord: %d HP\nHeroes gained: %d levels and %d items",
	"Души за волну: +%d · в запасе: %d": "Souls this wave: +%d · stored: %d",
	"ОТКРЫТА ВЕТКА: %s": "BRANCH UNLOCKED: %s",
	"Пережито волн: %d\nУбито героев: %d\nСлоёв глубины: %d  ·  Уровень Лорда: %d": "Waves survived: %d\nHeroes slain: %d\nDepth layers: %d  ·  Lord level: %d",
	"Рекорд: %d волн. Следующая крепость будет сильнее.": "Record: %d waves. Your next fortress will be stronger.",
	"+%d ПЕЧАТЕЙ ВЛАДЫКИ": "+%d LORD'S SEALS",
	"Волны: %d · герои: %d · особые отряды: %d · новые рубежи: %d": "Waves: %d · heroes: %d · special parties: %d · new milestones: %d",
	"Рекорд %d": "Record %d",
	"ЛАБИРИНТ · %s": "LABYRINTH · %s",
	"NO HERO RETURNS     /     ЛАБИРИНТ · %s": "NO HERO RETURNS     /     LABYRINTH · %s",
	"No Hero Returns · Лабиринт · %s": "No Hero Returns · Labyrinth · %s",
	"%s · мастерство %d/5": "%s · mastery %d/5",
	"%s · мастерство %d / 5": "%s · mastery %d / 5",
	"Печати Владыки: %d": "Lord's Seals: %d",
	"Лорды · %d печатей": "Lords · %d Seals",
	"В БОЙ · %s": "TO BATTLE · %s",
	"ПЕЧАТИ  %d": "SEALS  %d",
	"РЕКОРД  %d ВОЛН": "RECORD  %d WAVES",
	"ЛОРДЫ · %s": "LORDS · %s",
	"%s\nQ · %s — два заряда на волну.": "%s\nQ · %s — two charges per wave.",
	"Последний забег: +%d печатей": "Last run: +%d Seals",
	"В текущем забеге заработано: %d. Получите после его завершения.": "Earned this run: %d. Claim them when it ends.",
	"Мастерство %d / 5": "Mastery %d / 5",
	"Выбран · Мастерство %d / 5": "Selected · Mastery %d / 5",
	"Открыть: %d печатей": "Unlock: %d Seals",
	"Открыть и выбрать · %d печатей": "Unlock and select · %d Seals",
	"Мастерство %d / 5 · посмотреть дерево": "Mastery %d / 5 · view tree",
	"Мастерство %d": "Mastery %d",
	"После мастерства %d": "After mastery %d",
	"%d печатей · навсегда": "%d Seals · permanent",
	"%s · %d печатей": "%s · %d Seals",
	"Усиление способности · мастерство %d": "Ability upgrade · mastery %d",
	"Открыть Лорда · %d печатей": "Unlock Lord · %d Seals",
	"Не хватает %d печатей": "Need %d more Seals",
	"Мастерство %d · %d печатей": "Mastery %d · %d Seals",
	"Щит: %d%% максимального HP защитника.": "Shield: %d%% of the defender's maximum HP.",
	"Щит: %d%% максимального HP защитника. Три следующих удара: %s урона.": "Shield: %d%% of the defender's maximum HP. Next three strikes: %s damage.",
	"Одно возвращение с %d%% HP.": "One revival with %d%% HP.",
	"Одно возвращение с %d%% HP. После возвращения: %s урона.": "One revival with %d%% HP. After revival: %s damage.",
	"Яд: %d урона x %d тиков. Вспышка: %d урона. Учтена пассивная сила; навыки забега усиливают длительность.": "Poison: %d damage x %d ticks. Burst: %d damage. Includes passive power; run skills extend duration.",
	"%s открыт и выбран для нового забега.": "%s unlocked and selected for the next run.",
	"Мастерство повышено до %d. Усиление действует со следующего забега.": "Mastery increased to %d. The upgrade applies to the next run.",
	"Текущий забег закончится. Получите %d печатей за достигнутые результаты. Новый Лорд: %s.": "The current run will end. Receive %d Seals for your results. New Lord: %s.",
	"Текущий забег закончится; его %d печатей будут сохранены. В обучении — отдельное золото, без постоянных Печатей и рекордов. Прошлые достижения останутся с вами.": "The current run will end; its %d Seals will be saved. The tutorial uses separate gold and does not grant permanent Seals or records. Your past achievements are kept.",
	"Открывается победой на волне %d и остаётся в следующих забегах.": "Unlocks by defending wave %d and remains available in future runs.",
	"Волна %d": "Wave %d",
	"Ранг %d · %d зол.": "Rank %d · %d gold",
	"Ранг %d · развилки 2 / 5 / 15": "Rank %d · branches at 2 / 5 / 15",
	"Ранг %d · улучшить за %d зол.": "Rank %d · upgrade for %d gold",
	"Не хватает %d зол.": "Need %d more gold",
	"На ранге %d: %s": "At rank %d: %s",
	"Инструменты: %d · 50%% отключить ловушку на волну · одна попытка": "Tools: %d · 50%% chance to disable a trap for the wave · one attempt",
	"Инструменты: %d · все ловушки · раскрывает засады": "Tools: %d · all traps · reveals ambushes",
	"Яд: %d т.": "Poison: %d ticks",
	"%s: %d т.": "%s: %d ticks",
	"%s > следующий бой": "%s > next battle",
	"Кубок: %d/%d": "Chalice: %d/%d",
	"Комбо: %s": "Combo: %s",
	"Души: %d": "Souls: %d",
	"Изучить · %d душ": "Learn · %d souls",
	"Изучить · %s": "Learn · %s",
	"Изучен навык: %s": "Skill learned: %s",
	"%d / %d изучено · до конца забега · %s": "%d / %d learned · until the run ends · %s",
	"покупка один раз за души · бой на паузе": "buy once with souls · combat paused",
	"просмотр; покупки между волнами · бой на паузе": "view only; purchase between waves · combat paused",
	"%s · %d душ": "%s · %d souls",
	"Владыка: %s": "Lord: %s",
	"Найдено: %d": "Found: %d",
	"Текущие шансы:\nОбычный герой: %d%% — 0, %d%% — 1 душа.\nОсобый герой: %d%% — 0, %d%% — 1, %d%% — 2 души.\nНулевых наград подряд: %d / 2.": "Current chances:\nOrdinary hero: %d%% — 0, %d%% — 1 soul.\nSpecial hero: %d%% — 0, %d%% — 1, %d%% — 2 souls.\nConsecutive zero rewards: %d / 2.",
	"Текущие шансы:\nОбычный герой: %d%% — 0, %d%% — 1 душа.\nОсобый герой: %d%% — 0, %d%% — 1, %d%% — 2 души.\nНулевых наград подряд: %d / 2. Следующая душа гарантирована.": "Current chances:\nOrdinary hero: %d%% — 0, %d%% — 1 soul.\nSpecial hero: %d%% — 0, %d%% — 1, %d%% — 2 souls.\nConsecutive zero rewards: %d / 2. The next soul is guaranteed.",
	"Возвращаются к выходу · несут %d зол.": "Returning to the exit · carrying %d gold",
	"Исследуют подземелье · несут %d зол.": "Exploring the dungeon · carrying %d gold",
	"Раскопать клетку · %d зол.": "Dig cell · %d gold",
	"Ранг %d": "Rank %d",
	"Ранг %d · РУБЕЖ": "Rank %d · MILESTONE",
	"Ранг %d · Болты %d": "Rank %d · Bolts %d",
	"Ранг %d · РУБЕЖ · Болты %d": "Rank %d · MILESTONE · Bolts %d",
	"ОБЕЗВРЕЖЕНА · Болты %d": "DISARMED · Bolts %d",
	"ПРИВАЛ · %.1f с": "CAMP · %.1f s",
	"СЛОЙ %d · ДОСТУП ЗАКРЫТ": "LAYER %d · LOCKED",
	"СЛОЙ %d": "LAYER %d",
	"СОН · %d": "SLEEP · %d",
	"Сразу получить %d золота.": "Immediately gain %d gold.",
	"Сразу получить %d души текущего забега для навыков.": "Immediately gain %d run souls for skills.",
}
const CONTENT: Dictionary = {
	"Лагерь гоблинов": "Goblin Camp",
	"Гоблины": "Goblins",
	"Зал палача": "Executioner's Hall",
	"Палач": "Executioner",
	"Склеп стража": "Guardian's Crypt",
	"Страж": "Guardian",
	"Коридор шипов": "Spike Corridor",
	"Шипы": "Spikes",
	"Ядовитая камера": "Poison Chamber",
	"Яд": "Poison",
	"Паучье гнездо": "Spider Nest",
	"Пауки": "Spiders",
	"Мимик": "Mimic",
	"Логово огра": "Ogre Den",
	"Огр": "Ogre",
	"Псарня охотника": "Hunter's Kennels",
	"Гончая": "Hound",
	"Зал призрака": "Wraith Hall",
	"Призрак": "Wraith",
	"Покои вампира": "Vampire's Chambers",
	"Вампир": "Vampire",
	"Засадная баллиста": "Ambush Ballista",
	"Баллиста": "Ballista",
	"Пол вращающихся лезвий": "Spinning Blade Floor",
	"Лезвия": "Blades",
	"Зал оков": "Hall of Shackles",
	"Оковы": "Shackles",
	"Колокол безмолвия": "Bell of Silence",
	"Безмолвие": "Silence",
	"Ржавые руны": "Rust Runes",
	"Руны": "Runes",
	"Ржавчина": "Rust",
	"Комната": "Room",
	"Существо": "Creature",
	"Телесное": "Corporeal",
	"Дух": "Spirit",
	"Ловушка": "Trap",
	"Засада": "Ambush",
	"Броня": "Armor",
	"Дешёвый заслон. При поражении отдаёт героям 5 XP: несколько слабых комнат могут подарить им уровень.": "An inexpensive barrier. Defeating it grants heroes 5 XP: several weak rooms can give them a level.",
	"Мощный удар по переднему герою. При поражении отдаёт 3 XP и меч с +3 к урону.": "A powerful strike against the front hero. Defeating it grants 3 XP and a sword with +3 damage.",
	"Живучий защитник с небольшим уроном: затягивает бой, пока яд повреждает отряд. Если прямо перед ним стоят оковы, комбо «Темница» лишает героев атак в первый тик. При поражении отдаёт 3 XP.": "A durable defender with low damage: prolongs combat while poison hurts the party. Shackles directly before it enable the Dungeon Cell combo, preventing hero attacks on the first tick. Defeating it grants 3 XP.",
	"Наносит прямой урон переднему герою в обход брони. Следопыт с инструментом снижает урон на 60%; защитные ветки ловушки сопротивляются. Наград героям нет.": "Deals direct damage to the front hero, bypassing armor. A Ranger with a tool reduces damage by 60%; defensive trap branches resist this. Grants no rewards to heroes.",
	"Отравляет всех героев: 2 урона за тик, 8 тиков. Яд обходит броню и усиливает пауков. Наград героям нет.": "Poisons all heroes: 2 damage per tick for 8 ticks. Poison bypasses armor and empowers spiders. Grants no rewards to heroes.",
	"Добивает героя с наименьшей долей HP, предпочитая отравленных. По отравленной цели +3 урона. При поражении отдаёт 3 XP.": "Targets the hero with the lowest HP percentage, preferring poisoned heroes. Deals +3 damage to poisoned targets. Defeating it grants 3 XP.",
	"Существо с засадой: прыгает в тыл, предпочитая поддержку и заклинателей. Живой следопыт ослабляет первый удар на 35%. При поражении отдаёт 3 XP и щит с +1 к броне.": "An ambush creature that leaps into the rear, preferring support heroes and spellcasters. A living Ranger weakens its first strike by 35%. Defeating it grants 3 XP and a shield with +1 armor.",
	"Выдерживает затяжной бой. Каждый третий боевой тик удар дубиной наносит ×1,5 урона.": "Endures prolonged combat. Every third combat tick, its club deals ×1.5 damage.",
	"Атакует героя с наименьшей долей HP. Если у цели осталось 40% HP или меньше, наносит на 30% больше урона.": "Attacks the hero with the lowest HP percentage. Deals 30% more damage if the target has 40% HP or less.",
	"Дух: рыцарь и варвар наносят ему на 20% меньше урона, чародей — на 25% больше. Призрачный клинок игнорирует 2 брони героя; защита рыцаря от телесных существ не действует.": "A spirit: Knights and Barbarians deal 20% less damage to it; Mages deal 25% more. Its spectral blade ignores 2 hero armor; the Knight's protection against corporeal creatures does not apply.",
	"Лечится на 25% фактически нанесённого урона, если пережил ответный удар. Лечение не воскрешает и не превышает максимальный HP.": "Heals for 25% of actual damage dealt if it survives the counterattack. Healing cannot revive it or exceed maximum HP.",
	"Стреляет в последнего живого героя группы в обход брони. Следопыт ослабляет выстрел, пока у него есть инструменты.": "Shoots the last living hero in the party, bypassing armor. A Ranger weakens the shot while tools remain.",
	"Наносит урон каждому живому герою в обход брони. Следопыт ослабляет механизм, пока у него есть инструменты.": "Damages every living hero, bypassing armor. A Ranger weakens the mechanism while tools remain.",
	"Сковывает героев на первые 2 тика следующего боя: каждый чётный тик они пропускают обычную атаку. Следопыт с инструментом сокращает эффект до 1 тика. Рядом перед стражем открывает комбо «Темница». Наград героям нет.": "Shackles heroes for the first 2 ticks of the next battle: they skip normal attacks on every even tick. A Ranger with a tool shortens the effect to 1 tick. Placing it directly before a Guardian enables the Dungeon Cell combo. Grants no rewards to heroes.",
	"В следующем бою на первые 3 тика подавляет магию чародея, песню барда, лечение и защиту от яда жрицы. Ярость варвара и навыки следопыта действуют. Следопыт с инструментом сокращает эффект до 1 тика. Наград героям нет.": "For the first 3 ticks of the next battle, suppresses Mage magic, Bard songs, Priestess healing and poison protection. Barbarian rage and Ranger skills still work. A Ranger with a tool shortens the effect to 1 tick. Grants no rewards to heroes.",
	"В следующем бою снижает броню всех героев на 1 первые 3 тика; ниже нуля броня не падает. Следопыт с инструментом сокращает эффект до 1 тика. Наград героям нет.": "Reduces all heroes' armor by 1 for the first 3 ticks of the next battle; armor cannot fall below zero. A Ranger with a tool shortens the effect to 1 tick. Grants no rewards to heroes.",
	"Наносит прямой урон переднему герою в обход брони.": "Deals direct damage to the front hero, bypassing armor.",
	"Отравляет всех героев: 2 урона за тик, 8 тиков.": "Poisons all heroes: 2 damage per tick for 8 ticks.",
	"Стреляет в последнего живого героя группы в обход брони.": "Shoots the last living hero in the party, bypassing armor.",
	"Наносит урон каждому живому герою в обход брони.": "Damages every living hero, bypassing armor.",
	"Сковывает героев на первые 2 тика следующего боя: каждый чётный тик они пропускают обычную атаку.": "Shackles heroes for the first 2 ticks of the next battle: they skip normal attacks on every even tick.",
	"В следующем бою на первые 3 тика подавляет магию чародея, песню барда, лечение и защиту от яда жрицы.": "For the first 3 ticks of the next battle, suppresses Mage magic, Bard songs, Priestess healing and poison protection.",
	"В следующем бою снижает броню всех героев на 1 первые 3 тика; ниже нуля броня не падает.": "Reduces all heroes' armor by 1 for the first 3 ticks of the next battle; armor cannot fall below zero.",
	"Рыцарь": "Knight",
	"Следопыт": "Ranger",
	"Жрица": "Priestess",
	"Чародей": "Mage",
	"Варвар": "Barbarian",
	"Бард": "Bard",
	"Защитник · против телесных существ: +25% урона и −20% получаемого урона. Духам наносит на 20% меньше урона. Бонус защиты не действует против духов, ловушек и Лорда.": "Defender · against corporeal creatures: +25% damage dealt and −20% damage taken. Deals 20% less damage to spirits. Its defense bonus does not apply against spirits, traps or the Lord.",
	"Разведчик · ослабляет все ловушки за инструменты: прямой урон −60%, яд до 3 тиков, контроль до 1 тика; защитные ветки ловушек сопротивляются. Запас 2 + 1 каждые 6 волн. Пока жив, снижает первый удар существ с засадой на 35% без инструмента. Без брони.": "Scout · spends tools to weaken traps: direct damage −60%, poison shortened to 3 ticks, control to 1 tick; defensive trap branches resist this. Starts with 2 tools, plus 1 every 6 waves. While alive, reduces ambush creatures' first strike by 35% without using a tool. No armor.",
	"Лекарь · каждый третий боевой тик лечит самого раненого союзника. Пока жива и не под безмолвием, весь отряд получает на 25% меньше урона яда. Ауры не складываются; с алхимиками защита ограничена 50%. Уязвима к атакам в тыл.": "Healer · heals the most wounded ally every third combat tick. While alive and not silenced, reduces the party's poison damage taken by 25%. Auras do not stack; protection combined with alchemists is capped at 50%. Vulnerable to rear attacks.",
	"Заклинатель · +25% урона духам. Каждый третий боевой тик: ×1,5 урона и игнорирование 1 брони. Безмолвие подавляет оба эффекта. Хрупкий, уязвим к атакам в тыл.": "Spellcaster · +25% damage to spirits. Every third combat tick: ×1.5 damage and ignores 1 armor. Silence suppresses both effects. Fragile and vulnerable to rear attacks.",
	"Берсерк · +20% урона телесным существам, −20% урона духам. При HP ≤ 40% ярость даёт ещё +25% урона и действует под безмолвием. Без брони: уязвим к ловушкам и добиванию.": "Berserker · +20% damage to corporeal creatures, −20% damage to spirits. At HP ≤ 40%, rage grants another +25% damage and works while silenced. No armor: vulnerable to traps and finishing blows.",
	"Поддержка · пока жив и не под безмолвием, даёт +15% урона всему отряду, включая себя. Несколько песен не складываются. Слаб в одиночку, уязвим к атакам в тыл.": "Support · while alive and not silenced, grants +15% damage to the whole party, including itself. Multiple songs do not stack. Weak alone and vulnerable to rear attacks.",
	"Падший рыцарь": "Fallen Knight",
	"Рыцарь-послушник": "Novice Knight",
	"Учебный противник: 120 HP, 4 урона. Способность Владыки активируется вручную.": "Training opponent: 120 HP, 4 damage. Cast the Lord's power manually.",
	"Первый налёт · обучение": "First raid · tutorial",
	"Рыцарь-послушник покажет работу комнат и способности Владыки.": "The Novice Knight lets you practice using rooms and the Lord's power.",
	"Военный лагерь": "War Camp",
	"Знаменосец": "Standard Bearer",
	"Чёрный штандарт": "Black Standard",
	"Подрывники": "Saboteurs",
	"Пороховая мастерская": "Powder Workshop",
	"Пороховой погреб": "Powder Cellar",
	"Карманники": "Pickpockets",
	"Шайка грабителей": "Thieves' Gang",
	"Воровской король": "Thief King",
	"Разведчик отмечает героя. Первый удар следующего соседнего существа направляется по метке.": "The scout marks a hero. The next adjacent creature's first attack targets that hero.",
	"Сигнальная башня направляет два первых удара соседа по отмеченной цели.": "The signal tower directs the next creature's first two attacks at the marked hero.",
	"Военачальник под чёрным знаменем направляет три первых удара соседа.": "The commander under the black banner directs the next creature's first three attacks.",
	"После поражения гоблинов бочка взрывается перед передним героем.": "When the goblins fall, a barrel explodes in front of the lead hero.",
	"В затяжном бою гоблины один раз бросают бомбу; после поражения взрывается бочка.": "In a long fight, the goblins throw one bomb. A barrel explodes when they fall.",
	"Финальный взрыв порохового погреба ранит весь отряд.": "The powder cellar's final explosion wounds the entire party.",
	"Первый успешный удар крадёт бонус оружия героя до конца боя с гоблинами.": "The first successful hit steals the hero's weapon bonus until the fight ends.",
	"Шайка выбирает героя с наиболее выгодным оружием.": "The gang targets the hero with the most valuable weapon.",
	"Король временно крадёт оружие и защитный предмет. После боя вещи возвращаются.": "The king temporarily steals a weapon and a defensive item. Both return when the fight ends.",
	"Бесплатное развитие": "Free evolution",
	"Страж последнего рубежа": "Guardian of the Last Stand",
	"Укрепляет прислужников и прикрывает защитника, которому предстоит принять удар.": "Strengthens minions and protects the defender about to take a hit.",
	"+10% HP существ во всех комнатах.": "+10% creature HP in all rooms.",
	"Железная воля": "Iron Will",
	"Даёт текущему защитнику щит и усиливает три следующих удара. Работает и на Владыке.": "Shields the current defender and strengthens its next three strikes. Also works on the Lord.",
	"Боевой обет": "Battle Oath",
	"Щит и три усиленных удара текущего защитника.": "A shield and three empowered strikes for the current defender.",
	"Несокрушимый бастион": "Unbreakable Bastion",
	"Щит сильнее на 20 процентных пунктов, усиления ударов нет.": "Shield strength increases by 20 percentage points; strikes are not empowered.",
	"Некромант": "Necromancer",
	"Хозяин возвращённых": "Master of the Returned",
	"Лишает героев части опыта и позволяет выбранному защитнику пережить смертельный удар.": "Reduces heroes' experience gains and lets the chosen defender survive a lethal blow.",
	"Герои получают на 15% меньше XP за существ.": "Heroes gain 15% less XP from creatures.",
	"Восстань": "Rise Again",
	"Помечает текущего защитника: после смертельного урона он один раз возвращается с частью HP. Работает и на Владыке.": "Marks the current defender: after lethal damage, it returns once with a portion of its HP. Also works on the Lord.",
	"Печать возврата": "Seal of Return",
	"Возвращает помеченного защитника с частью максимального HP.": "Revives the marked defender with a portion of its maximum HP.",
	"Мстительный призрак": "Vengeful Revenant",
	"Возвращает на 10 процентных пунктов меньше HP, зато даёт +30% урона до конца боя в комнате.": "Revives with 10 percentage points less HP, but grants +30% damage until combat in the room ends.",
	"Чумной алхимик": "Plague Alchemist",
	"Мастер ядов": "Master of Poisons",
	"Продлевает отравление и наказывает группы, уже ослабленные ядовитыми камерами.": "Extends poison and punishes parties already weakened by poison chambers.",
	"+20% длительности яда.": "+20% poison duration.",
	"Чумной выброс": "Plague Burst",
	"Отравляет всех живых героев. Те, кто был отравлен до применения, дополнительно получают мгновенный урон.": "Poisons all living heroes. Heroes already poisoned before use also take instant damage.",
	"Яд на всю группу и вспышка по уже отравленным героям.": "Poisons the whole party and bursts on heroes already poisoned.",
	"Едкая вспышка": "Caustic Burst",
	"Мгновенный урон ×1,5, но длительность накладываемого яда меньше на 2 тика.": "Instant damage ×1.5, but applied poison lasts 2 fewer ticks.",
	"Лаборатория": "Laboratory",
	"Казармы": "Barracks",
	"Мастерская": "Workshop",
	"Яд действует на 2 тика дольше; HP существ −15%.": "Poison lasts 2 ticks longer; creature HP −15%.",
	"HP существ +25%; урон ловушек −15%.": "Creature HP +25%; trap damage −15%.",
	"Урон ловушек +25%; урон существ −10%.": "Trap damage +25%; creature damage −10%.",
	"Орда": "Horde",
	"Ковен": "Coven",
	"Механизмы": "Mechanisms",
	"Меч палача": "Executioner's Sword",
	"Щит мимика": "Mimic's Shield",
	"Охота на отравленных": "Poison Hunt",
	"Темница": "Dungeon Cell",
	"Эхо механизмов": "Echo of Mechanisms",
	"Знамя засады": "Ambush Banner",
	"Печать дани": "Tithe Seal",
	"Клятва склепа": "Crypt Oath",
	"Золотой тайник": "Gold Cache",
	"Кубок восстановления": "Restoration Chalice",
	"Сгусток душ": "Soul Cluster",
	"Первый удар каждого существа в каждой волне наносит на 15% больше урона. На Владыку не действует.": "Each creature's first strike in every wave deals 15% more damage. Does not affect the Lord.",
	"За каждую следующую отражённую волну: ещё 2 золота.": "Each subsequent defended wave grants 2 extra gold.",
	"Все стражи склепа получают +1 брони. Работает также у купленных позже стражей.": "All Crypt Guardians gain +1 armor, including Guardians purchased later.",
	"Сразу восстановить до 50% максимального HP Владыки, не превышая максимум. Не воскрешает.": "Immediately restore up to 50% of the Lord's maximum HP without exceeding the maximum. Cannot revive.",
	"Босс: Клятва пяти": "Boss: Oath of Five",
	"Клятва пяти": "Oath of Five",
	"Одинокий рыцарь": "Lone Knight",
	"Разведка подземелья": "Dungeon Scouts",
	"Паломница": "Pilgrim",
	"Священный дозор": "Holy Watch",
	"Осторожные искатели": "Cautious Seekers",
	"Магический конвой": "Arcane Convoy",
	"Боевой напев": "Battle Chant",
	"Опытные приключенцы": "Veteran Adventurers",
	"Чародейская свита": "Arcane Retinue",
	"Налёт охотников": "Hunters' Raid",
	"Братство пламени": "Brotherhood of Flame",
	"Искатели реликвий": "Relic Seekers",
	"Штурмовая дружина": "Assault Company",
	"Сила I": "Strength I",
	"+8% урона существ. Складывается с другими узлами Силы; Лорда и ловушки не усиливает.": "+8% creature damage. Stacks with other Strength nodes; does not strengthen the Lord or traps.",
}
const ERRORS: Dictionary = {
	"Такого Владыки нет.": "That Lord does not exist.",
	"Этот Владыка уже открыт.": "This Lord is already unlocked.",
	"Не хватает Печатей Владыки: нужно %d.": "Not enough Lord's Seals: %d required.",
	"Сначала откройте этого Владыку.": "Unlock this Lord first.",
	"Достигнут максимальный уровень мастерства.": "Maximum mastery level reached.",
	"Такого варианта способности нет.": "That ability variant does not exist.",
	"Нужно мастерство уровня %d.": "Requires mastery level %d.",
	"Владыку выбирают до первого рейда нового забега.": "Choose your Lord before the first raid of a new run.",
	"Неизвестный Владыка.": "Unknown Lord.",
	"После покупки навыков Владыка закреплён за текущим забегом.": "Buying skills locks your Lord choice for the current run.",
	"Для этого забега Владыка не выбран.": "No Lord selected for this run.",
	"Способность доступна во время рейда.": "This ability is available during a raid.",
	"Владыка погиб.": "The Lord has fallen.",
	"Заряды этой волны закончились.": "No charges left this wave.",
	"Не хватает золота: нужно %d.": "Not enough gold: %d required.",
	"Дождитесь боя с живым защитником.": "Wait for combat with a living defender.",
	"Защитник ещё выходит из-за решётки.": "The defender is still emerging from behind the gate.",
	"Сейчас нет активного боя.": "No active combat.",
	"Способность применяется в боевой комнате или тронном зале.": "Use this ability in a combat room or the throne room.",
	"У этого защитника ещё действует предыдущий щит или усиление.": "This defender's previous shield or boost is still active.",
	"Этот защитник уже отмечен для возвращения.": "This defender is already marked for revival.",
	"Строительство доступно между волнами.": "Build between waves.",
	"Выберите строительный слот.": "Choose a building space.",
	"Казна и трон занимают отдельные места.": "The treasury and throne occupy their own spaces.",
	"Этот слот уже занят. Выберите пустое место.": "This space is occupied. Choose an empty space.",
	"Это место занимает пасть живой комнаты.": "A Living Chamber's maw occupies this space.",
	"Такой комнаты нет.": "That room does not exist.",
	"Сначала выберите чертёж этой комнаты после волны.": "First choose this room's blueprint after a wave.",
	"Запас этой комнаты на текущую волну закончился.": "This room is out of stock for the current wave.",
	"Перестановка доступна между волнами.": "Move rooms between waves.",
	"Выберите два строительных слота.": "Choose two building spaces.",
	"Сначала выберите построенную комнату.": "Select a built room first.",
	"Улучшения доступны между волнами.": "Upgrade between waves.",
	"Выберите построенную комнату.": "Select a built room.",
	"Комната достигла максимального ранга %d.": "The room has reached its maximum rank of %d.",
	"Продажа доступна между волнами.": "Sell between waves.",
	"Этаж можно купить между волнами.": "Buy a floor between waves.",
	"Сейчас нет нового этажа для настройки.": "No new floor to configure.",
	"Выберите свойство из предложенных.": "Choose one of the offered traits.",
	"Ветку комнаты выбирают между волнами.": "Choose room branches between waves.",
	"Ветка недоступна: нужен ранг 2 и ещё не выбранная специализация.": "Branch unavailable: requires rank 2 and no specialization selected yet.",
	"Развитие комнаты доступно между волнами.": "Develop rooms between waves.",
	"Выберите доступную ступень развития этой комнаты.": "Choose an available development stage for this room.",
	"Настройка доступна между волнами.": "Configure between waves.",
	"Такой вариант сейчас недоступен.": "That option is currently unavailable.",
	"Сейчас нет доступной сделки.": "No deal available.",
	"Для сделки выберите пустое место.": "Choose an empty space for the deal.",
	"Лечение доступно между волнами.": "Heal between waves.",
	"Лорд уже полностью здоров.": "The Lord is already at full health.",
	"Сначала завершите текущую волну и выберите усиления.": "Finish the current wave and choose your upgrades first.",
	"Лорд погиб. Начните новый забег.": "The Lord has fallen. Start a new run.",
	"Текущая волна ещё не завершена.": "The current wave has not ended yet.",
	"Неизвестный навык.": "Unknown skill.",
	"Уже изучено в этом забеге.": "Already learned this run.",
	"Скрытый привод временно недоступен: его новый эффект после переделки обезвреживания ещё не выбран.": "Hidden Drive is temporarily unavailable: its new effect after the disarming rework has not been chosen yet.",
	"Покупка навыков доступна между волнами.": "Purchase skills between waves.",
	"Нужен Владыка: %s.": "Requires Lord: %s.",
	"Сначала изучите: %s.": "Learn first: %s.",
	"Нужно изучить хотя бы один соединённый навык.": "Learn at least one connected skill.",
	"Не хватает душ: нужно %d.": "Not enough souls: %d required.",
	"Не удалось изучить навык": "Could not learn the skill",
	"Не удалось изучить навык.": "Could not learn the skill.",
	"Сейчас нет доступного чертежа.": "No blueprint available.",
	"Выберите один из предложенных чертежей.": "Choose one of the offered blueprints.",
	"Сейчас нет доступной реликвии.": "No relic available.",
	"Выберите одну из предложенных реликвий.": "Choose one of the offered relics.",
	"У этой реликвии нет доступного эффекта.": "This relic has no available effect.",
	"Кубок не может воскресить погибшего Владыку.": "The Chalice cannot revive a fallen Lord.",
	"Сейчас нет лагеря для срыва.": "No camp to interrupt.",
	"Отдых уже завершён.": "The rest has already ended.",
	"В этом лагере больше нет доступного лечения.": "No healing remains at this camp.",
	"Казна и трон не могут занимать место другой комнаты.": "The treasury and throne cannot occupy another room's space.",
	"Проходы меняются между волнами.": "Change passages between waves.",
	"Такой общей границы нет.": "That shared boundary does not exist.",
	"Казна и трон перемещаются между волнами.": "Move the treasury and throne between waves.",
	"Выберите свободное место.": "Choose an empty space.",
	"Трон и казна должны стоять отдельно.": "The throne and treasury must occupy separate spaces.",
	"Раскопка доступна между волнами.": "Dig between waves.",
	"Выше входного слоя копать нельзя.": "You cannot dig above the entrance layer.",
	"Сначала откройте следующий слой глубины.": "Unlock the next depth layer first.",
	"Выберите новую клетку рядом с подземельем.": "Choose a new cell next to the dungeon.",
	"Это место уже недоступно для раскопки.": "This space is no longer available for digging.",
	"Доступ к глубине покупают между волнами.": "Unlock deeper layers between waves.",
	"Граница больше недоступна. Выберите её на карте заново.": "This boundary is no longer available. Select it on the map again.",
}
