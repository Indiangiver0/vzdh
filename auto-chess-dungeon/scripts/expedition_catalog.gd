extends RefCounted
## Run-only choices and readable party templates. No state or random draws here.

static func blueprint_ids() -> Array[String]:
	return ["shackles", "silence", "rust", "guardian", "ogre", "war_hound", "wraith", "vampire", "ballista", "blade_floor"]


static func combos() -> Array[Dictionary]:
	return [
		{"id": "venom_hunt", "name": "Охота на отравленных", "first": "poison", "second": "spider", "description": "Пауки получают обычный бонус +3 урона по отравленным. Соседний яд готовит им цель; отдельный бонус не складывается."},
		{"id": "marked_ambush", "name": "Засада", "first": "goblin", "second": "executioner", "description": "Гоблины отмечают последнюю атакованную цель. Первый удар соседнего палача по живой отмеченной цели: +15% урона."},
		{"id": "dungeon_cell", "name": "Темница", "first": "shackles", "second": "guardian", "description": "В первом тике боя с соседним стражем герои пропускают обычные атаки. Лечение и яд действуют; эффект не повторяется."},
	]


static func relics() -> Array[Dictionary]:
	return [
		{"id": "trap_echo", "name": "Эхо механизмов", "description": "Первая ловушка каждого этажа за волну даёт слабое эхо: 40% урона шипов, баллисты, лезвий или тика яда (не менее 1); контроль действует на 1 тик дольше (до 6).", "icon": "res://assets/icons/spikes.svg"},
		{"id": "war_banner", "name": "Знамя засады", "description": "Первый удар каждого существа в каждой волне наносит на 15% больше урона. На Владыку не действует.", "icon": "res://assets/icons/executioner.svg"},
		{"id": "tithe_seal", "name": "Печать дани", "description": "За каждую следующую отражённую волну: ещё 2 золота.", "icon": "res://assets/icons/goblin.svg"},
		{"id": "guardian_oath", "name": "Клятва склепа", "description": "Все стражи склепа получают +1 брони. Работает также у купленных позже стражей.", "icon": "res://assets/icons/guardian.svg"},
	]


static func relic(id: String) -> Dictionary:
	for definition in relics():
		if str(definition.id) == id:
			return definition.duplicate(true)
	return {}


static func party_templates(wave: int) -> Array[Dictionary]:
	if wave <= 3:
		return [
			{"ids": ["knight"], "name": "Одинокий рыцарь", "description": "Рыцарь силён против существ; ловушки обходят его защитную стойку."},
			{"ids": ["rogue"], "name": "Разведка подземелья", "description": "Следопыт ослабляет ловушки, пока не закончатся инструменты."},
			{"ids": ["priest"], "name": "Паломница", "description": "Жрица лечит себя каждый третий тик. Мимик достаёт поддержку."},
		]
	if wave <= 7:
		var pairs: Array[Dictionary] = [
			{"ids": ["knight", "priest"], "name": "Священный дозор", "description": "Рыцарь прикрывает жрицу. Яд и охота на тыл мешают лечению."},
			{"ids": ["rogue", "priest"], "name": "Осторожные искатели", "description": "Инструменты и лечение помогают пережить ловушки, но авангард слабее."},
			{"ids": ["knight", "mage"], "name": "Магический конвой", "description": "Рыцарь прикрывает чародея: каждый третий удар мага сильнее и обходит 1 брони."},
		]
		if wave >= 6:
			pairs.append({"ids": ["barbarian", "bard"], "name": "Боевой напев", "description": "Бард усиливает союзника на 15%; раненый варвар добавляет 25% урона. Уберите поддержку."})
		return pairs
	return [
		{"ids": ["knight", "rogue", "priest"], "name": "Опытные приключенцы", "description": "Сбалансированная экспедиция: защита, инструменты и лечение."},
		{"ids": ["knight", "mage", "bard"], "name": "Чародейская свита", "description": "Бард усиливает чародея за рыцарем. Безмолвие задерживает песни и заклинания."},
		{"ids": ["barbarian", "rogue", "bard"], "name": "Налёт охотников", "description": "Следопыт ослабляет ловушки, бард усиливает варвара. Лечения нет."},
		{"ids": ["barbarian", "mage", "priest"], "name": "Братство пламени", "description": "Маг пробивает броню, жрица удерживает варвара в бою. Особенно опасна затяжная схватка."},
		{"ids": ["rogue", "mage", "priest"], "name": "Искатели реликвий", "description": "Инструменты и магия поддержаны лечением, но нет рыцарского прикрытия."},
		{"ids": ["knight", "barbarian", "bard"], "name": "Штурмовая дружина", "description": "Два бойца под песней барда. Нет лечения и обезвреживания ловушек."},
	]
