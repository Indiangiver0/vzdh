extends RefCounted
## Lessons advance after successful actions on the real labyrinth.

const Language = preload("res://scripts/game_language.gd")
const LESSONS: Dictionary = {
	"excavate": ["excavate:(0, 2)", "close_side_path", "Нажмите на золотой плюс под первой комнатой. Раскопка стоит 4 золота.", "Tap the gold plus below the first room. Excavation costs 4 gold."],
	"close_side_path": ["boundary:edge:0:4", "select_goblin", "Нажмите на золотой кружок у новой клетки. Крестик означает закрытый проход.", "Tap the gold marker by the new cell to close that passage."],
	"select_goblin": ["shop:goblin", "place_goblin", "Выберите гоблинов в магазине.", "Choose Goblins in the Shop."],
	"place_goblin": ["slot:0", "select_executioner", "Поставьте гоблинов в золотую клетку сразу за входом.", "Place the Goblins in the highlighted cell just past the entrance."],
	"select_executioner": ["shop:executioner", "place_executioner", "Выберите палача в магазине.", "Choose the Executioner in the Shop."],
	"place_executioner": ["slot:1", "info_treasury", "Поставьте палача в соседнюю золотую клетку. Вместе с гоблинами он устроит засаду.", "Place the Executioner in the next highlighted cell. Together they set up an ambush."],
	"info_treasury": ["lesson_next", "info_abilities", "К казне нужен путь от входа в обход трона. Если герои доберутся до казны, они украдут половину текущего золота и могут уйти с добычей. Победите носителей, чтобы вернуть золото.", "The treasury needs a route from the entrance that bypasses the throne. Heroes who reach it steal half your current gold and may retreat with it. Defeat the carriers to recover the gold."],
	"info_abilities": ["lesson_next", "start", "Q применяет силу Лорда. Оба заряда за волну стоят золота, цена видна на кнопке. E срывает привал. Первый срыв за волну бесплатный, второй стоит 25% базового дохода волны, следующие — по 50%.", "Q casts your Lord's power. Each of its two casts per wave costs the gold shown on the button. E interrupts a camp. The first interruption per wave is free, the second costs 25% of base wave income, and later ones cost 50% each."],
	"start": ["start", "ability_wait", "Защита готова. Нажмите «Начать волну».", "Your defenses are ready. Start the wave."],
	"ability": ["ability", "watch", "Бой на паузе. Нажмите Q внизу, чтобы заплатить за щит защитника.", "Combat is paused. Tap Q below to pay for a shield on your defender."],
	"reward": ["continue", "learn_skill", "Посмотрите награды за волну и нажмите «Продолжить».", "Review the wave rewards and press Continue."],
	"learn_skill": ["skill_bought", "move_room", "Откройте «Навыки» и купите начальный навык за душу. Навыки усиливают весь забег.", "Open Skills and buy a starting skill for one soul. Skills strengthen your whole run."],
	"move_room": ["move:0:1", "select_upgrade", "Зажмите гоблинов и перетащите их на палача. На телефоне сначала удержите палец. Занятые комнаты поменяются местами бесплатно.", "Hold and drag the Goblins onto the Executioner. On a phone, press and hold before moving. The occupied rooms swap for free."],
	"select_upgrade": ["slot:1", "upgrade", "Выберите перемещённых гоблинов в золотой клетке.", "Select the moved Goblins in the highlighted cell."],
	"upgrade": ["upgrade", "evolution", "Нажмите «Улучшить» и заплатите золото за ранг 2. На телефоне сначала откройте «Сведения».", "Pay gold to Upgrade the room to rank 2. On a phone, open Details first."],
	"evolution": ["evolution_choice", "floor", "Выберите ветку гоблинов. Развитие меняет способность комнаты.", "Choose a Goblin evolution. This changes the room's ability."],
	"floor": ["floor", "floor_choice", "Купите следующий слой кнопкой «Глубже». На телефоне она в окне «Карта». Ниже откроются места для раскопки и строительства.", "Buy the next layer with Dig Deeper. On a phone, find it under Map. This unlocks lower cells to excavate and build in."],
	"floor_choice": ["floor_choice", "finish", "Выберите свойство нового слоя. Клетки в нём раскапываются отдельно.", "Choose a trait for the new layer. Its cells are excavated separately."],
}

var step: String = ""


func begin() -> void:
	step = "excavate"


func active() -> bool:
	return not step.is_empty()


func allows(action: String) -> bool:
	if not active():
		return true
	if LESSONS.has(step) and action == str(LESSONS[step][0]):
		return true
	match step:
		"place_goblin":
			return action == "shop:goblin"
		"place_executioner":
			return action == "shop:executioner"
		"watch":
			return action in ["pause", "speed", "ability"]
		"learn_skill":
			return action == "skills"
		"upgrade", "evolution":
			return action == "slot:1"
		"floor_choice":
			return action == "choice"
	return false


func accepted(action: String) -> void:
	if LESSONS.has(step) and action == str(LESSONS[step][0]):
		step = str(LESSONS[step][1])


func observe(game) -> bool:
	if not active():
		return false
	if game.phase == "defeat":
		step = "defeat"
	elif game.phase == "result":
		step = "reward"
	elif step == "ability_wait" and bool(game.ability_status().get("can_cast", false)):
		step = "ability"
		return true
	return false


func target() -> String:
	match step:
		"learn_skill":
			return "skills"
		"move_room":
			return "slot:0"
		"floor_choice":
			return "choice"
	return str(LESSONS[step][0]) if LESSONS.has(step) else ""


func prompt(_phase: String) -> String:
	var english: bool = Language.is_english()
	if LESSONS.has(step):
		return str(LESSONS[step][3 if english else 2])
	match step:
		"ability_wait":
			return "Heroes move and fight automatically. Your Lord's power will be ready shortly." if english else "Герои идут и сражаются сами. Скоро можно будет применить силу Лорда."
		"watch":
			return "The shield is active. Use the controls below to pause or change speed." if english else "Щит применён. Пауза и скорость доступны внизу."
		"finish":
			return "Lesson complete. Start your own dungeon." if english else "Урок пройден. Начните своё подземелье."
		"defeat":
			return "Your training throne fell. Retry the lesson or start your own run." if english else "Учебный трон пал. Повторите урок или начните свой забег."
	return ""


func context_hint(_area: String) -> Dictionary:
	return {}
