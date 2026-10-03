extends RefCounted
## Presentation state only. Every step follows a successful model action.

var step: String = ""

func begin() -> void:
	step = "select_goblin"

func active() -> bool:
	return not step.is_empty()

func allows(action: String) -> bool:
	if not active():
		return true
	match step:
		"select_goblin":
			return action == "shop:goblin"
		"place_goblin":
			return action == "slot:0" or action == "shop:goblin"
		"select_executioner":
			return action == "shop:executioner"
		"place_executioner":
			return action == "slot:1" or action == "shop:executioner"
		"start":
			return action == "start"
		"ability":
			return action == "ability"
		"watch":
			return action in ["pause", "speed", "ability"]
		"select_upgrade":
			return action == "slot:0"
		"evolution":
			return action in ["slot:0", "upgrade", "evolution", "evolution_choice"]
		"upgrade":
			# The first tap selects the room; the second can open its mobile popup.
			return action in ["slot:0", "upgrade"]
		"floor":
			return action == "floor"
	return false

func accepted(action: String) -> void:
	var transitions: Dictionary = {
		"select_goblin": ["shop:goblin", "place_goblin"],
		"place_goblin": ["slot:0", "select_executioner"],
		"select_executioner": ["shop:executioner", "place_executioner"],
		"place_executioner": ["slot:1", "start"],
		"start": ["start", "ability_wait"],
		"ability": ["ability", "watch"],
		"reward": ["continue", "choices"],
		"select_upgrade": ["slot:0", "upgrade"],
		"upgrade": ["upgrade", "evolution"],
		"evolution": ["evolution_choice", "floor"],
		"floor": ["floor", "floor_choice"],
		"floor_choice": ["floor_choice", "finish"],
	}
	var transition: Array = transitions.get(step, [])
	if not transition.is_empty() and action == str(transition[0]):
		step = str(transition[1])

func observe(game) -> bool:
	# Return true only when the first valid combat needs to pause for Q.
	if not active():
		return false
	if game.phase == "defeat":
		step = "defeat"
	elif game.phase == "result":
		step = "reward"
	elif step == "choices" and game.phase == "prepare":
		step = "select_upgrade"
	elif step == "ability_wait" and bool(game.ability_status().get("can_cast", false)):
		step = "ability"
		return true
	return false

func target() -> String:
	match step:
		"select_goblin":
			return "shop:goblin"
		"select_executioner":
			return "shop:executioner"
		"place_goblin", "select_upgrade":
			return "slot:0"
		"place_executioner":
			return "slot:1"
		"start", "ability", "upgrade", "floor":
			return step
		"evolution":
			return "evolution_choice"
		"reward":
			return "continue"
		"choices", "floor_choice":
			return "choice"
	return ""

func prompt(phase: String) -> String:
	if step == "choices":
		match phase:
			"level_up":
				return "Выберите талант: он усиливает эту попытку. Польза и небольшой штраф написаны на карте."
			"blueprint":
				return "Выберите чертёж: новая комната попадёт в магазин этого забега. Подберите будущую связку."
			"relic":
				return "Выберите реликвию: её правило действует на всё подземелье до конца забега."
	var prompts: Dictionary = {
		"select_goblin": "Откройте магазин и выберите подсвеченную карточку гоблинов.",
		"place_goblin": "Поставьте гоблинов в первое место: герои идут слева направо и сначала встретят их.",
		"select_executioner": "Теперь выберите палача: вместе с гоблинами он образует боевую связку.",
		"place_executioner": "Поставьте палача сразу после гоблинов. Для комбо нужны соседние места в этом порядке.",
		"start": "Связка «Засада» готова — видна золотая стрелка! Гоблины ставят метку, палач бьёт сильнее. Начните волну.",
		"ability_wait": "Герои идут сами, защитники сражаются сами. Скоро попробуем вашу силу Лорда.",
		"ability": "Бой на паузе. Нажмите Q или золотую кнопку: щит защитит текущего бойца. Зарядов всего два на волну.",
		"watch": "Сила применена! Наблюдайте за боем. Пробел ставит паузу, ×2 / ×4 ускоряют время.",
		"reward": "Первая победа! Золото идёт на комнаты, опыт — на таланты. Нажмите «Продолжить», чтобы выбрать награды.",
		"select_upgrade": "Выберите гоблинов в первом месте. На телефоне нажмите дважды, чтобы открыть окно комнаты.",
		"upgrade": "Нажмите «Улучшить»: ранг вырастет, затем сразу появится выбор ветки. На телефоне повторное нажатие на комнату открывает её окно.",
		"evolution": "Выберите ветку гоблинов. На рангах 5 и 15 появятся следующие решения.",
		"floor": "Купите следующий этаж: ещё пять мест перед троном.",
		"floor_choice": "Выберите свойство нового этажа. Оно усиливает все пять мест — планируйте, что поставить на них.",
		"finish": "Готово! На втором этаже путь идёт справа налево. Трон всегда последний; комбо считайте по стрелкам пути.",
		"defeat": "Учебный трон пал. Можно повторить обучение или сразу начать своё подземелье.",
	}
	return str(prompts.get(step, "Следуйте золотой подсветке. Вы можете пропустить обучение в любой момент."))


func context_hint(area: String) -> Dictionary:
	if not active():
		return {}
	if area == "party" and step in ["select_goblin", "place_goblin"]:
		return {"title": "Сначала разведка", "text": "Следопыт тратит инструменты на первые ловушки. Мимик достаёт поддержку, паук выбирает ослабленных."}
	if area == "party" and step in ["ability_wait", "watch"]:
		return {"title": "У врага тоже есть прогресс", "text": "Побеждённые монстры дают героям опыт. Иногда пустая комната полезнее слабого защитника."}
	if area == "planning" and step in ["select_executioner", "place_executioner", "start"]:
		return {"title": "Цвет — это фракция", "text": "Гоблины и палач относятся к Орде. Два разных типа включают бонус; копии одного типа не увеличивают счётчик над полем."}
	if area == "planning" and step == "finish":
		return {"title": "Стройте глубже", "text": "Новый этаж добавляет пять мест. На втором этаже герои идут справа налево, трон остаётся последним."}
	return {}
