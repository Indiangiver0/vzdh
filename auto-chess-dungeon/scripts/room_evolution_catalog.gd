class_name RoomEvolutionCatalog
extends RefCounted
## Approved room mutations. Numbers are initial tuning, not measured balance.
## Cached records (including params) are read-only; callers store battle state elsewhere.

const TIERS: Array[int] = [2, 5, 15]
static var _paths: Dictionary = {}
static var _by_room: Dictionary = {}
static var _stages: Dictionary = {}


static func path(id: String) -> Dictionary:
	_ensure_catalog()
	return _paths.get(id.get_slice(":", 0), {})


static func paths(room_id: String) -> Array[Dictionary]:
	_ensure_catalog()
	var result: Array[Dictionary] = []
	result.assign(_by_room.get(room_id, []))
	return result


static func stage(path_id: String, rank: int) -> Dictionary:
	_ensure_catalog()
	var base_id: String = path_id.get_slice(":", 0)
	if not _paths.has(base_id) or rank < 2:
		return {}
	var tier: int = 15 if rank >= 15 else (5 if rank >= 5 else 2)
	return _stages.get(_stage_id(base_id, tier), {})


static func node(id: String) -> Dictionary:
	_ensure_catalog()
	return _stages.get(id, {})


static func path_ids() -> Array[String]:
	_ensure_catalog()
	var result: Array[String] = []
	result.assign(_paths.keys())
	return result


static func _stage_id(id: String, tier: int) -> String:
	return id if tier == 2 else "%s:%d" % [id, tier]


static func _register(room_id: String, id: String, names: Array, descriptions: Array, parameters: Array, counter: String) -> void:
	var stages: Array[Dictionary] = []
	for index in range(TIERS.size()):
		var tier: int = TIERS[index]
		var params: Dictionary = parameters[index]
		params.make_read_only()
		var record: Dictionary = {
			"id": _stage_id(id, tier), "path_id": id, "room_id": room_id,
			"name": str(names[index]), "description": str(descriptions[index]), "tier": tier,
			"visual_key": id, "mechanic": id, "params": params, "counter": counter,
			"evolution_path": id, "evolution_stage": tier,
		}
		record.make_read_only()
		stages.append(record)
		_stages[record.id] = record
	stages.make_read_only()
	var entry: Dictionary = {
		"id": id, "room_id": room_id, "name": str(names[0]),
		"description": str(descriptions[0]), "counter": counter,
		"visual_key": id, "mechanic": id, "stages": stages,
	}
	entry.make_read_only()
	_paths[id] = entry
	if not _by_room.has(room_id):
		_by_room[room_id] = []
	_by_room[room_id].append(entry)


static func _ensure_catalog() -> void:
	if not _paths.is_empty():
		return
	_spiders()
	_goblins()
	_executioners()
	_guardians()
	_ogres()
	_hounds()
	_poison_rooms()
	_mimics()
	_wraiths()
	_vampires()
	_spikes()
	_shackles()
	_bells()
	_rust_rooms()
	_ballistas()
	_blade_floors()
	for room_id in _by_room:
		_by_room[room_id].make_read_only()
	_paths.make_read_only()
	_by_room.make_read_only()
	_stages.make_read_only()


static func _spiders() -> void:
	_register("spider", "venom_hunter",
		["Ядовитый хищник", "Кислотный охотник", "Чумной пожиратель"],
		["Укусы оставляют яд на одной жертве. На клыках вырастают зелёные железы.",
		"Укус по отравленному расходует два тика яда во всплеск урона.",
		"Первая погибшая отравленная жертва заражает остальных. У гнезда видны раздутые ядовитые мешки."],
		[{"poison_damage_factor": 0.2, "poison_ticks": 3, "consume_ticks": 0, "death_spread": false},
		{"poison_damage_factor": 0.2, "poison_ticks": 4, "consume_ticks": 2, "death_spread": false},
		{"poison_damage_factor": 0.25, "poison_ticks": 4, "consume_ticks": 2, "death_spread": true, "spread_limit": 1}],
		"Жрица ослабляет яд; рыцарь и варвар сильны против тела паука.")
	_register("spider", "cocoon_weaver",
		["Прядильщик", "Ловчая паутина", "Коконщик"],
		["Липкие нити снижают следующую обычную атаку жертвы на 20%.",
		"Плотные нити ненадолго связывают одного героя. Смерть паука рвёт путы.",
		"Настоящий кокон отключает одного героя на 2 игровые секунды. Откат 8 секунд; применение заменяет атаку."],
		[{"slow_factor": 0.8, "duration_seconds": 0.0, "cooldown_seconds": 8.0, "warmup_seconds": 2.0},
		{"slow_factor": 0.8, "duration_seconds": 0.5, "cooldown_seconds": 8.0, "warmup_seconds": 2.0},
		{"slow_factor": 1.0, "duration_seconds": 2.0, "cooldown_seconds": 8.0, "warmup_seconds": 2.0}],
		"Следопыт сокращает плен. Пауза и скорость одинаково действуют на плен и откат.")
	_register("spider", "brood_mother",
		["Матка выводка", "Двойная кладка", "Королева гнезда"],
		["После смерти матки раскрываются яйца: два паучонка продолжают бой.",
		"Из двух кладок последовательно выходят две группы паучат.",
		"Пережив подготовку, матка выводит защитника ещё при жизни. Оставшиеся кладки раскрываются после смерти."],
		[{"brood_waves": 1, "brood_size": 2, "brood_hp_factor": 0.2, "brood_damage_factor": 0.35, "guardian_after_seconds": 0.0},
		{"brood_waves": 2, "brood_size": 2, "brood_hp_factor": 0.16, "brood_damage_factor": 0.3, "guardian_after_seconds": 0.0},
		{"brood_waves": 2, "brood_size": 2, "brood_hp_factor": 0.16, "brood_damage_factor": 0.3, "guardian_after_seconds": 3.0}],
		"Паучата не размножаются. Опыт и трофей общие для матки и всего выводка.")


static func _goblins() -> void:
	_register("goblin", "war_banner",
		["Военный лагерь", "Знаменосец", "Чёрный штандарт"],
		["Разведчик отмечает героя. Первый удар следующего соседнего существа направляется по метке.",
		"Сигнальная башня направляет два первых удара соседа по отмеченной цели.",
		"Военачальник под чёрным знаменем направляет три первых удара соседа."],
		[{"directed_hits": 1}, {"directed_hits": 2}, {"directed_hits": 3}],
		"Нужен следующий сосед с существом на том же этаже. Пустота и лестница обрывают приказ.")
	_register("goblin", "saboteurs",
		["Подрывники", "Пороховая мастерская", "Пороховой погреб"],
		["После поражения гоблинов бочка взрывается перед передним героем.",
		"В затяжном бою гоблины один раз бросают бомбу; после поражения взрывается бочка.",
		"Финальный взрыв порохового погреба ранит весь отряд."],
		[{"explosion_factor": 1.3, "throw_after_seconds": 0.0, "explosion_all": false},
		{"explosion_factor": 1.3, "throw_after_seconds": 2.0, "throw_factor": 0.7, "explosion_all": false},
		{"explosion_factor": 0.8, "throw_after_seconds": 2.0, "throw_factor": 0.7, "explosion_all": true}],
		"Следопыт ослабляет бомбы инструментом. Воскрешение не создаёт новую бочку.")
	_register("goblin", "pickpockets",
		["Карманники", "Шайка грабителей", "Воровской король"],
		["Первый успешный удар крадёт бонус оружия героя до конца боя с гоблинами.",
		"Шайка выбирает героя с наиболее выгодным оружием.",
		"Король временно крадёт оружие и защитный предмет. После боя вещи возвращаются."],
		[{"steal_slots": 1, "target_best_item": false}, {"steal_slots": 1, "target_best_item": true}, {"steal_slots": 2, "target_best_item": true}],
		"Без полезных вещей красть нечего. Классовые способности сохраняются.")


static func _executioners() -> void:
	_register("executioner", "guillotine",
		["Гильотинёр", "Эшафот", "Красная гильотина"],
		["Три обычные атаки взводят нож. Следующий тяжёлый удар находит самого раненого героя.",
		"Большой эшафот взводит лезвие за две обычные атаки; перед ударом виден замах.",
		"Красная гильотина наносит особенно тяжёлый удар раненому. Затем механизм заново взводится."],
		[{"charge_hits": 3, "heavy_factor": 1.7, "windup_rounds": 1}, {"charge_hits": 2, "heavy_factor": 1.7, "windup_rounds": 1}, {"charge_hits": 2, "heavy_factor": 2.1, "windup_rounds": 1}],
		"Удар можно пережить; гибель палача до окончания подготовки срывает казнь.")
	_register("executioner", "duelist",
		["Дуэлянт", "Арена суда", "Чёрный судья"],
		["Вызывает переднего героя на короткую дуэль. Лечение, песня и яд продолжают действовать.",
		"Ворота арены на три раунда оставляют обычные атаки только дуэлянтам.",
		"После паузы Чёрный судья может объявить вторую дуэль."],
		[{"duel_rounds": 2, "duel_uses": 1, "duel_cooldown_rounds": 8}, {"duel_rounds": 3, "duel_uses": 1, "duel_cooldown_rounds": 8}, {"duel_rounds": 3, "duel_uses": 2, "duel_cooldown_rounds": 8}],
		"Рыцарь и варвар опасны в поединке. Дуэль не блокирует поддержку.")
	_register("executioner", "cleaver",
		["Перерубатель", "Широкий тесак", "Багровый мясник"],
		["Избыточный урон добивания переходит на следующего живого героя.",
		"После первого убийства готовит один широкий удар с переносом избыточного урона.",
		"Огромный тесак делает подготовленное добивание особенно опасным для следующей цели."],
		[{"overkill_factor": 1.0, "followup_factor": 1.0, "followup_uses": 0}, {"overkill_factor": 1.0, "followup_factor": 1.35, "followup_uses": 1}, {"overkill_factor": 1.0, "followup_factor": 1.7, "followup_uses": 1}],
		"Без убийства переноса нет. Один удар переносится лишь один раз.")


static func _guardians() -> void:
	_register("guardian", "guardian_parry",
		["Караульный", "Щитоносец", "Капитан караула"],
		["Отбивает первый обычный удар и отвечает контратакой.",
		"Парирует первые удары двух разных героев; запас показан на щите.",
		"Большой щит отражает по одному обычному удару трёх разных героев."],
		[{"parry_charges": 1, "counter_factor": 0.65}, {"parry_charges": 2, "counter_factor": 0.65}, {"parry_charges": 3, "counter_factor": 0.65}],
		"Заряженное заклинание проходит через парирование. Против одной цели запас не повторяется.")
	_register("guardian", "guardian_aegis",
		["Хранитель эгиды", "Рунный бастион", "Бастион Ковена"],
		["Пережив первый раунд, заряжает руну. После гибели передаёт щит следующему соседнему существу.",
		"Светящийся канал передаёт соседу усиленный щит.",
		"После гибели стража над соседом раскрывается большой защитный купол."],
		[{"charge_rounds": 1, "shield_hp_factor": 0.2}, {"charge_rounds": 1, "shield_hp_factor": 0.3}, {"charge_rounds": 1, "shield_hp_factor": 0.4}],
		"Быстрая гибель не даёт заряда. Передача не пересекает пустоту, ловушки или лестницы.")
	_register("guardian", "guardian_possessed",
		["Одержимый страж", "Треснувший саркофаг", "Освобождённый дух"],
		["После разрушения тела из трещин выходит слабый дух и продолжает бой.",
		"Каменная оболочка скрывает полноценного призрачного защитника.",
		"Расколотый саркофаг выпускает сильного духа: физический урон ×0,2, магический ×1,5."],
		[{"spirit_hp_factor": 0.25, "spirit_damage_factor": 0.6}, {"spirit_hp_factor": 0.35, "spirit_damage_factor": 0.8}, {"spirit_hp_factor": 0.45, "spirit_damage_factor": 1.0}],
		"Переход один за бой. Опыт общий для обеих фаз; чародей эффективен против духа.")


static func _ogres() -> void:
	_register("ogre", "ogre_earthshaker",
		["Сотрясатель", "Каменный громила", "Горный крушитель"],
		["Подняв дубину, бьёт по полу и ранит весь отряд.",
		"Каменный столб обрушивает потолочную пыль и волну удара на всех героев.",
		"Огромная колонна раскалывает пол. Между замахами огр атакует обычно."],
		[{"windup_rounds": 2, "heavy_factor": 0.65, "cooldown_rounds": 4}, {"windup_rounds": 2, "heavy_factor": 0.8, "cooldown_rounds": 4}, {"windup_rounds": 2, "heavy_factor": 1.0, "cooldown_rounds": 4}],
		"Герои могут убить огра во время замаха. Распределённый удар хуже добивает одну цель.")
	_register("ogre", "ogre_stonethrower",
		["Камнемёт", "Метатель валунов", "Осадный исполин"],
		["Готовит бросок камня в заднего героя, остальные удары направляет вперёд.",
		"Большой валун и метка над жертвой показывают грядущий бросок в тыл.",
		"Примитивная праща выпускает особенно тяжёлый камень в отмеченного героя."],
		[{"windup_rounds": 2, "heavy_factor": 1.4, "cooldown_rounds": 4}, {"windup_rounds": 2, "heavy_factor": 1.65, "cooldown_rounds": 4}, {"windup_rounds": 2, "heavy_factor": 1.9, "cooldown_rounds": 4}],
		"Без тыла специальной выгоды нет. Физические бойцы опасны во время долгой подготовки.")
	_register("ogre", "ogre_maneater",
		["Людоед", "Костяная кухня", "Пожиратель знамён"],
		["После первого личного убийства тратит действие на пир, затем восстанавливает 20% HP.",
		"В мясницкой кухне переживший пир огр возвращает 30% HP.",
		"Пиршественный зал позволяет восстановить 40% HP после первого убийства."],
		[{"heal_fraction": 0.2, "feast_rounds": 1, "uses": 1}, {"heal_fraction": 0.3, "feast_rounds": 1, "uses": 1}, {"heal_fraction": 0.4, "feast_rounds": 1, "uses": 1}],
		"Во время пира не атакует. Один пир за бой; мёртвый огр не лечится.")


static func _hounds() -> void:
	_register("war_hound", "war_hound_hellfire",
		["Адская гончая", "Огненные врата", "Пепельный Цербер"],
		["Готовит выдох. Обычные атаки героев на горящей дорожке вызывают ожог.",
		"Широкий выдох поджигает проход. Лечение и магические приёмы ожог не вызывают.",
		"Три пылающие пасти превращают весь зал в огненное поле на ограниченное время."],
		[{"windup_rounds": 2, "fire_rounds": 3, "burn_factor": 0.2, "cooldown_rounds": 10}, {"windup_rounds": 2, "fire_rounds": 4, "burn_factor": 0.25, "cooldown_rounds": 10}, {"windup_rounds": 2, "fire_rounds": 5, "burn_factor": 0.3, "cooldown_rounds": 10}],
		"Выдох заменяет атаку. Смерть гончей гасит огонь; пожары не складываются.")
	_register("war_hound", "war_hound_lycanthrope",
		["Лунная гончая", "Оборотень", "Кровавый оборотень"],
		["При HP ниже 40% живой пёс превращается в оборотня, сохраняя оставшееся здоровье.",
		"Оборотень вытаскивает поддержку вперёд до своей смерти. Способности жертвы продолжают работать.",
		"Крупный оборотень удерживает строй захватом; после его смерти прежний порядок сразу возвращается."],
		[{"transform_hp_fraction": 0.4, "transformed_damage_factor": 1.2, "pull_support": false, "restore_on_death": true}, {"transform_hp_fraction": 0.4, "transformed_damage_factor": 1.2, "pull_support": true, "restore_on_death": true}, {"transform_hp_fraction": 0.4, "transformed_damage_factor": 1.4, "pull_support": true, "restore_on_death": true}],
		"Смертельный удар не даёт превратиться. Один захват; рыцарь возвращается сразу после смерти зверя.")
	_register("war_hound", "war_hound_sapper_hunter",
		["Ищейка сапёров", "Ловец сумок", "Разрыватель сумок"],
		["Первой добычей выбирает следопыта. Успешный укус уничтожает один инструмент на эту волну.",
		"Бронированный намордник помогает добраться до сапёрной сумки; затем гончая охотится на раненых.",
		"Большая ищейка разрывает сумку, оставляя будущие ловушки опаснее. Потеря по-прежнему одна."],
		[{"tools_destroyed": 1, "sapper_bite_factor": 1.0}, {"tools_destroyed": 1, "sapper_bite_factor": 1.15}, {"tools_destroyed": 1, "sapper_bite_factor": 1.3}],
		"Без следопыта с инструментами приём бесполезен. Обычный укус остаётся физическим.")


static func _poison_rooms() -> void:
	_register("poison", "poison_fog_crypt",
		["Туманный склеп", "Газовые цистерны", "Блуждающий мор"],
		["Облако следует за героями и дважды обновляет яд в следующем бою.",
		"Густой туман хранит три конечных выброса для следующего боя.",
		"Четыре выброса газа распределяются на два следующих боя."],
		[{"pulses": 2, "battles": 1, "pulse_interval_rounds": 2, "poison_ticks": 3}, {"pulses": 3, "battles": 1, "pulse_interval_rounds": 2, "poison_ticks": 3}, {"pulses": 4, "battles": 2, "pulse_interval_rounds": 2, "poison_ticks": 3}],
		"Следопыт сокращает запас газа; жрица ослабляет яд. Пустые клетки не создают выбросов.")
	_register("poison", "poison_spore_garden",
		["Сад спор", "Грибной питомник", "Моровой сад"],
		["Одна спора на герое лопается после трёх его атак, отравляя остальных.",
		"Зрелая спора раскрывается после двух атак носителя.",
		"Гибель носителя тоже выпускает спору. Вспышка не заражает новыми спорами."],
		[{"attacks_to_burst": 3, "death_burst": false, "poison_ticks": 4}, {"attacks_to_burst": 2, "death_burst": false, "poison_ticks": 4}, {"attacks_to_burst": 2, "death_burst": true, "poison_ticks": 4}],
		"Следопыт повреждает гриб, жрица защищает от яда. До разрыва массового отравления нет.")
	_register("poison", "poison_distiller",
		["Алхимический дожигатель", "Реактор яда", "Великая перегонная"],
		["Снимает яд одной цели, превращая половину оставшегося урона в немедленную реакцию.",
		"Аппарат перерабатывает отравление двух героев.",
		"Лаборатория по отдельности расходует яд каждого отравленного героя."],
		[{"targets": 1, "remaining_poison_factor": 0.5}, {"targets": 2, "remaining_poison_factor": 0.55}, {"targets": 99, "remaining_poison_factor": 0.6}],
		"Без яда реакции нет. Следопыт ослабляет аппарат; защита жрицы действует на вспышку.")


static func _mimics() -> void:
	_register("mimic", "mimic_weapon_swap",
		["Проклятая оружейная", "Мастер подделок", "Арсенал обмана"],
		["Подменяет оружие одного героя: обычные удары слабее на 20% до конца волны.",
		"Выбирает самого опасного вооружённого бойца и подменяет его оружие.",
		"Арсенал подменяет оружие двух героев. Повторные подделки не складываются."],
		[{"targets": 1, "damage_factor": 0.8, "best_weapon": false, "duration": "through_current_wave"}, {"targets": 1, "damage_factor": 0.8, "best_weapon": true, "duration": "through_current_wave"}, {"targets": 2, "damage_factor": 0.8, "best_weapon": true, "duration": "through_current_wave"}],
		"Следопыт распознаёт первую подделку. Броня и классовые способности сохраняются.")
	_register("mimic", "mimic_false_treasury",
		["Ложная сокровищница", "Беглый сундук", "Зал ложных богатств"],
		["Первая направленная атака попадает в пустой сундук. Обманка не атакует и не даёт XP.",
		"Раненый мимик один раз меняет оболочку и оставляет ещё одну обманку.",
		"Роскошная сокровищница скрывает подмену оболочки; обе обманки остаются конечными."],
		[{"decoys": 1, "relocate_hp_fraction": 0.0, "relocate_decoys": 0}, {"decoys": 1, "relocate_hp_fraction": 0.5, "relocate_decoys": 1}, {"decoys": 1, "relocate_hp_fraction": 0.65, "relocate_decoys": 1}],
		"Живой следопыт сразу обнаруживает настоящего мимика.")
	_register("mimic", "mimic_living_chamber",
		["Живая комната", "Прорастающий зал", "Пожирающий чертог"],
		["Сам зал становится мимиком: двери-челюсти, язык-пол и одно уязвимое сердце.",
		"Занимает одно соседнее пустое место дополнительной пастью, атакующей вместе с центром.",
		"Две боковые пасти занимают пустые места того же этажа. Центр и отростки имеют одно сердце."],
		[{"extensions": 0, "extension_damage_factor": 0.3}, {"extensions": 1, "extension_damage_factor": 0.3}, {"extensions": 2, "extension_damage_factor": 0.3}],
		"Постройки и границы этажа ограничивают рост. Смерть центра убирает все пасти; следопыт находит сердце.")
	_register("mimic", "mimic_cursed_gift",
		["Проклятая сокровищница", "Зубастая приманка", "Сокровищница предательства"],
		["Дарит лечебный кубок. В следующих боях он лечит носителя раз за бой; после третьего применения кусает его и исчезает.",
		"После каждого лечения на кубке растут зубы. Третий глоток заканчивается усиленным укусом.",
		"Роскошный подарок скрывает большую пасть. Три настоящих лечения готовят особенно опасный укус."],
		[{"heal_fraction": 0.08, "bite_fraction": 0.3, "uses_to_bite": 3, "uses_per_battle": 1},
		{"heal_fraction": 0.08, "bite_fraction": 0.38, "uses_to_bite": 3, "uses_per_battle": 1},
		{"heal_fraction": 0.08, "bite_fraction": 0.45, "uses_to_bite": 3, "uses_per_battle": 1}],
		"Следопыт распознаёт подарок. На коротком маршруте кубок может только помочь героям: до третьего лечения дело не дойдёт.")


static func _wraiths() -> void:
	_register("wraith", "wraith_twilight_hall",
		["Зал сумерек", "Теневой фонарь", "Врата теней"],
		["Следующий соседний телесный защитник становится духом на волну: физический урон ×0,2, магический ×1,5.",
		"Поток тумана делает связь с призрачным соседом видимой; способность существа сохраняется.",
		"Можно направить покров на предыдущего соседа. Одновременно защищает только одно существо."],
		[{"physical_factor": 0.2, "magic_factor": 1.5, "choose_previous": false}, {"physical_factor": 0.2, "magic_factor": 1.5, "choose_previous": false}, {"physical_factor": 0.2, "magic_factor": 1.5, "choose_previous": true}],
		"Чародей опасен для обоих духов. Пустота, ловушки и лестницы обрывают связь; трон не преобразуется.")
	_register("wraith", "wraith_banshee",
		["Баньши", "Плачущий склеп", "Траурный хор"],
		["В начале боя готовит один магический крик по всему отряду вместо обычных атак.",
		"Светящаяся пасть и траурные полотнища готовят сильный общий крик.",
		"Успешный крик оставляет один слабый отзвук в следующем бою."],
		[{"windup_rounds": 3, "scream_factor": 1.4, "echo_factor": 0.0}, {"windup_rounds": 3, "scream_factor": 1.7, "echo_factor": 0.0}, {"windup_rounds": 3, "scream_factor": 1.7, "echo_factor": 0.35}],
		"Заряженное заклинание чародея срывает подготовку и отзвук. Гибель до крика тоже его отменяет.")
	_register("wraith", "wraith_throne_guardian",
		["Страж трона", "Печать телохранителя", "Призрачный бастион"],
		["Герои проходят алтарь без боя. Этот дух принимает удары у трона, пока Лорд атакует.",
		"Печать вызывает укреплённого призрачного телохранителя рядом с Лордом.",
		"Большой алтарь готовит сильного стража для последнего боя. После его гибели герои бьют Лорда."],
		[{"reserve_hp_factor": 1.0, "reserve_damage_factor": 0.0, "reserve_count": 1}, {"reserve_hp_factor": 1.2, "reserve_damage_factor": 0.0, "reserve_count": 1}, {"reserve_hp_factor": 1.4, "reserve_damage_factor": 0.0, "reserve_count": 1}],
		"Алтарь занимает место без защиты по дороге. Чародей эффективен против призрачного телохранителя.")


static func _vampires() -> void:
	_register("vampire", "vampire_hypnotist",
		["Гипнотизёр", "Алый салон", "Кровавый граф"],
		["Готовит взгляд: опасный боец наносит свой следующий обычный удар союзнику.",
		"Граф выбирает сильнейшего бойца; красная печать показывает готовящийся перехват.",
		"После длинной паузы может провести вторую попытку гипноза."],
		[{"windup_rounds": 2, "hypnosis_uses": 1, "cooldown_rounds": 10}, {"windup_rounds": 2, "hypnosis_uses": 1, "cooldown_rounds": 10}, {"windup_rounds": 2, "hypnosis_uses": 2, "cooldown_rounds": 10}],
		"Заряженное заклинание срывает подготовку. Гипноз перехватывает один обычный удар, не способности.")
	_register("vampire", "vampire_sire",
		["Обращающий", "Гроб слуги", "Кровавый двор"],
		["Первый лично добитый герой становится одним слугой только на следующую волну.",
		"Слуга выходит из своего гроба и применяет один приём прежнего класса.",
		"Перед следующей волной можно выбрать одного слугу среди лично добитых кандидатов."],
		[{"servant_hp_factor": 0.3, "servant_damage_factor": 0.3, "class_skill": false, "choose_candidate": false}, {"servant_hp_factor": 0.35, "servant_damage_factor": 0.35, "class_skill": true, "choose_candidate": false}, {"servant_hp_factor": 0.4, "servant_damage_factor": 0.4, "class_skill": true, "choose_candidate": true}],
		"Слуга живёт одну волну, сам не обращает. Его сила зависит от комнаты; армия не копится.")
	_register("vampire", "vampire_sarcophagus_master",
		["Хозяин гроба", "Каменный саркофаг", "Хозяин саркофага"],
		["При HP не выше 35% один раз за волну вампир улетает в разрушаемый гроб. Через 3 шага рейда восстанавливает 35% максимального HP и ждёт следующего боя.",
		"Каменный саркофаг имеет 30% базового HP вампира. Восстановление за 3 шага рейда лечит на 40% максимального HP.",
		"После восстановления на 40% максимального HP вампир вступает в бой с одним усиленным укусом: ×1,8 урона."],
		[{"hide_hp_fraction": 0.35, "coffin_hp_factor": 0.2, "ritual_rounds": 3, "heal_fraction": 0.35, "bite_factor": 1.0}, {"hide_hp_fraction": 0.35, "coffin_hp_factor": 0.3, "ritual_rounds": 3, "heal_fraction": 0.4, "bite_factor": 1.0}, {"hide_hp_fraction": 0.35, "coffin_hp_factor": 0.3, "ritual_rounds": 3, "heal_fraction": 0.4, "bite_factor": 1.8}],
		"Гроб находится в самой далёкой от входа доступной клетке того же слоя; без другой клетки остаётся на месте. Его можно разбить до пробуждения. Готовый вампир защищает свою клетку или присоединяется к следующему бою с существом или Лордом. Смертельный удар до ухода убивает сразу.")


static func _spikes() -> void:
	_register("spikes", "spikes_armour_press",
		["Шипастый пресс", "Сходящиеся стены", "Замковый пресс"],
		["Вес брони запускает потолочный пресс. Чем больше брони, тем сильнее удар, до предела.",
		"Шипастые стены сжимают бронированную цель с двух сторон.",
		"Огромный замковый пресс особенно опасен тяжёлому доспеху."],
		[{"base_damage_factor": 0.6, "damage_per_armor": 3, "bonus_cap": 18}, {"base_damage_factor": 0.6, "damage_per_armor": 4, "bonus_cap": 24}, {"base_damage_factor": 0.6, "damage_per_armor": 5, "bonus_cap": 30}],
		"Следопыт заклинивает механизм. Против лёгкой брони слабее обычных шипов.")
	_register("spikes", "spikes_blood_surge",
		["Кровожадные колья", "Алый частокол", "Кровавый залп"],
		["Добивание переднего героя запускает один залп по остальным.",
		"Кровь зажигает руны частокола и усиливает залп после убийства.",
		"Большие полые колья выпускают мощную волну шипов после личного добивания."],
		[{"surge_factor": 0.4, "surge_uses": 1}, {"surge_factor": 0.55, "surge_uses": 1}, {"surge_factor": 0.7, "surge_uses": 1}],
		"Без добивания залпа нет; залп не вызывает новый залп. Следопыт ослабляет весь механизм.")
	_register("spikes", "spikes_collapsing_walkway",
		["Провальный настил", "Ломкий мост", "Мост над кольями"],
		["Первый герой проходит безопасно, следующий проваливается на колья.",
		"Две слабые секции моста ранят героев за передним бойцом.",
		"Большой настил обрушивается под всеми, кроме ведущего. Герои выбираются и продолжают путь."],
		[{"rear_targets": 1, "damage_factor": 0.9}, {"rear_targets": 2, "damage_factor": 0.8}, {"rear_targets": 99, "damage_factor": 0.9}],
		"Против одиночки бесполезен. Следопыт ослабляет падение; этаж и порядок отряда не меняются.")


static func _shackles() -> void:
	_register("shackles", "shackles_shared_chain",
		["Общая цепь", "Цепи узников", "Тройные оковы"],
		["Связывает двух героев. Один удар делится: 75% жертве, 25% связанному союзнику.",
		"Три расходуемых звена позволяют разделить три попадания между двумя героями.",
		"Троих героев соединяет цепь с четырьмя передачами. Общий урон не увеличивается."],
		[{"linked_targets": 2, "charges": 1, "share_fraction": 0.25}, {"linked_targets": 2, "charges": 3, "share_fraction": 0.25}, {"linked_targets": 3, "charges": 4, "share_fraction": 0.25}],
		"Следопыт ослабляет связь. Переданный урон не передаётся снова; цепь может помешать добиванию.")
	_register("shackles", "shackles_prisoner_scales",
		["Весы узников", "Рунные весы", "Весы равновесия"],
		["Перераспределяет HP между двумя героями, приближая их доли здоровья друг к другу.",
		"Точные весы сильнее выравнивают долю здоровья пары.",
		"Один раз выравнивает долю HP двух героев, сохраняя суммарное здоровье."],
		[{"equalize_fraction": 0.5}, {"equalize_fraction": 0.75}, {"equalize_fraction": 1.0}],
		"Следопыт уменьшает перенос. Мёртвые не воскресают; раненый герой может получить пользу.")
	_register("shackles", "shackles_garrison_gallery",
		["Решётчатый караул", "Общая галерея", "Караульный двор"],
		["Два следующих соседних существа проводят общий бой. Второй выходит после короткой задержки.",
		"Открытые решётки ускоряют выход второго защитника в общий зал.",
		"Оба защитника выходят вместе и сохраняют собственные HP и награды."],
		[{"join_delay_rounds": 2, "disarmed_extra_rounds": 2, "max_defenders": 2}, {"join_delay_rounds": 1, "disarmed_extra_rounds": 2, "max_defenders": 2}, {"join_delay_rounds": 0, "disarmed_extra_rounds": 2, "max_defenders": 2}],
		"Нужны ровно два существа подряд на том же этаже. Следопыт задерживает второго; повторного боя нет.")


static func _bells() -> void:
	_register("silence", "silence_black_mass",
		["Чёрная месса", "Тёмная часовня", "Великая месса"],
		["В следующем бою перехватывает половину одного лечения жрицы в пользу защитника.",
		"Часовня перехватывает 75% первого лечения; оставшаяся часть достаётся герою.",
		"Месса переносит одно лечение защитнику. Ритуальная чаша сразу трескается."],
		[{"redirect_fraction": 0.5, "uses": 1}, {"redirect_fraction": 0.75, "uses": 1}, {"redirect_fraction": 1.0, "uses": 1}],
		"Следопыт ослабляет перехват. Без жрицы пользы нет; мёртвый или здоровый защитник лечения не получает.")
	_register("silence", "silence_null_bell",
		["Колокол очищения", "Рунная звонница", "Нулевой свод"],
		["В начале следующего боя снимает по одному временному эффекту с обеих сторон.",
		"Кольцевая волна снимает до двух эффектов, в том числе твой яд и щиты.",
		"Большой свод очищает все временные эффекты. Песня барда вскоре возвращается."],
		[{"effects_per_actor": 1, "aura_suppression_rounds": 1}, {"effects_per_actor": 2, "aura_suppression_rounds": 1}, {"effects_per_actor": 99, "aura_suppression_rounds": 2}],
		"Очищение одно, классы и постоянные вещи сохраняются. Следопыт уменьшает число снимаемых эффектов.")
	_register("silence", "silence_funeral_peal",
		["Похоронный звон", "Башня свечей", "Траурная звонница"],
		["Первая смерть героя в следующем бою ненадолго подавляет магическую поддержку выживших.",
		"Погребальная свеча запускает более долгий звон после первой потери.",
		"Тёмная волна на три раунда отключает лечение, песню и заклинания после первой смерти."],
		[{"silence_rounds": 1, "uses": 1}, {"silence_rounds": 2, "uses": 1}, {"silence_rounds": 3, "uses": 1}],
		"Следопыт сокращает подавление. Без смерти заряд пропадает; обычные атаки и ярость работают.")


static func _rust_rooms() -> void:
	_register("rust", "rust_fracture_window",
		["Кузница трещин", "Кузница клещей", "Разжиматель лат"],
		["В начале следующего боя раскрывает 1 броню цели на три раунда.",
		"Призрачные клещи раздвигают 2 брони на короткое время.",
		"Большая кузница раскрывает 3 брони, затем пластины снова смыкаются."],
		[{"armor_reduction": 1, "duration_rounds": 3}, {"armor_reduction": 2, "duration_rounds": 3}, {"armor_reduction": 3, "duration_rounds": 3}],
		"Следопыт ослабляет раскрытие. Против безбронных бесполезна; магия не получает усиления.")
	_register("rust", "rust_shard_chamber",
		["Осколочная камера", "Осколочный барабан", "Раскалённая печь"],
		["Вытягивает металл из брони и выпускает один ограниченный залп по отряду.",
		"Барабан превращает больше брони в разлетающиеся осколки.",
		"Печь выпускает большой залп. Доспех сразу собирается обратно, штраф не остаётся."],
		[{"damage_per_armor": 3, "damage_cap": 12}, {"damage_per_armor": 4, "damage_cap": 18}, {"damage_per_armor": 5, "damage_cap": 25}],
		"Без брони нет металла. Следопыт ослабляет залп; осколки не порождают новые залпы.")
	_register("rust", "rust_reforging",
		["Переплавка", "Щитовая кузница", "Великая литейная"],
		["На следующий соседний бой забирает 1 броню героя и отливает из неё щит защитнику.",
		"Щитовая форма перерабатывает до 2 брони в конечный запас защиты.",
		"Литейная забирает до 3 брони. После боя доспех возвращается, остаток щита исчезает."],
		[{"armor_reduction": 1, "shield_per_armor": 8, "shield_cap": 8}, {"armor_reduction": 2, "shield_per_armor": 9, "shield_cap": 18}, {"armor_reduction": 3, "shield_per_armor": 10, "shield_cap": 30}],
		"Нужны броня и следующий соседний защитник того же этажа. Следопыт уменьшает эффект.")


static func _ballistas() -> void:
	_register("ballista", "ballista_clear_sight",
		["Баллиста прострела", "Стрелковая площадка", "Осадная вышка"],
		["Через одно пустое место поддерживает бой предыдущего защитника одним выстрелом.",
		"Поднятая площадка выпускает более сильный болт через пустой проход.",
		"Вышка простреливает одну или две пустые клетки того же этажа."],
		[{"max_empty_slots": 1, "shot_factor": 1.0, "shots_per_wave": 1}, {"max_empty_slots": 1, "shot_factor": 1.15, "shots_per_wave": 1}, {"max_empty_slots": 2, "shot_factor": 1.15, "shots_per_wave": 1}],
		"Постройки и лестницы перекрывают огонь. Следопыт ослабляет болт; при подходе повторного выстрела нет.")
	_register("ballista", "ballista_reserve_magazine",
		["Запасной арсенал", "Оружейный склад", "Большой арсенал"],
		["Каждая новая волна добавляет один болт до запаса 2. На героя расходуется не более одного болта.",
		"Закрытый склад сохраняет до 3 болтов между волнами.",
		"Большой магазин вмещает 4 болта. Пустое орудие не стреляет."],
		[{"capacity": 2, "reload_per_wave": 1, "shot_factor": 0.8}, {"capacity": 3, "reload_per_wave": 1, "shot_factor": 0.8}, {"capacity": 4, "reload_per_wave": 1, "shot_factor": 0.8}],
		"Следопыт ослабляет залп одним инструментом. Меню, перенос и улучшение боеприпасов не добавляют.")
	_register("ballista", "ballista_siege",
		["Осадная баллиста", "Тяжёлое копьеметание", "Замковый копьемёт"],
		["Один болт пробивает двух героев, теряя силу на второй цели.",
		"Тяжёлое копьё проходит до трёх участников строя.",
		"Осадный станок лучше сохраняет силу копья после пробития."],
		[{"targets": 2, "shot_factor": 0.8, "falloff": 0.6}, {"targets": 3, "shot_factor": 0.8, "falloff": 0.6}, {"targets": 3, "shot_factor": 0.8, "falloff": 0.75}],
		"Следопыт ослабляет весь выстрел одним инструментом. Против одиночки хуже обычной баллисты.")


static func _blade_floors() -> void:
	_register("blade_floor", "blade_floor_blood_mill",
		["Кровавая мельница", "Режущие ворота", "Большая кровавая мельница"],
		["Герои проходят две последовательные пилы вместо одного мгновенного удара.",
		"Три режущие секции включаются по очереди; между ними жрица может лечить.",
		"Четыре секции завершаются большим маховиком. Пройденная пила останавливается."],
		[{"sections": 2, "section_damage_factor": 0.55, "section_interval_rounds": 1}, {"sections": 3, "section_damage_factor": 0.4, "section_interval_rounds": 1}, {"sections": 4, "section_damage_factor": 0.35, "section_interval_rounds": 1}],
		"Следопыт останавливает часть секций. Проход конечный и занимает одно место.")
	_register("blade_floor", "blade_floor_partition_corridor",
		["Коридор перегородок", "Раздельные проходы", "Раздвижной лабиринт"],
		["В следующем соседнем бою решётки на два раунда мешают героям помогать друг другу.",
		"Три отдельных прохода временно оставляют лечение и песню только их владельцам.",
		"Высокий лабиринт разделяет поддержку на четыре раунда, затем уходит в пол."],
		[{"partition_rounds": 2}, {"partition_rounds": 3}, {"partition_rounds": 4}],
		"Все продолжают атаковать. Следопыт открывает проходы раньше; нужен сосед на том же этаже.")
	_register("blade_floor", "blade_floor_corpse_reclaimer",
		["Мельница костей", "Костедробилка", "Погребальная мельница"],
		["Перерабатывает останки предыдущего соседнего защитника: герои теряют 20% его XP. Урона не наносит.",
		"Закрытая костедробилка забирает 30% опыта за окончательное поражение соседа.",
		"Большая мельница забирает 40% XP. Оставшийся опыт всегда получают герои."],
		[{"xp_reduction_fraction": 0.2}, {"xp_reduction_fraction": 0.3}, {"xp_reduction_fraction": 0.4}],
		"Следопыт уменьшает потерю XP. Один общий бюджет соседа; воскрешение и кладки не дают повторных срабатываний.")
