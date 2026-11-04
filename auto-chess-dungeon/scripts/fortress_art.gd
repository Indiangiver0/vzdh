extends RefCounted
## Cached, presentation-only fortress art. Call draw_* from a CanvasItem draw pass.
## Coordinates stay in the caller's current drawing transform; no model or RNG access.

const MANIFEST_PATH: String = "res://assets/fortress/manifest.json"
const STONE_FILL: Color = Color("282b2b")
const TERRAIN_TILE_SIZE: float = 512.0
const TERRAIN_TINT: Color = Color(0.62, 0.62, 0.62, 1.0)

static var _manifest_loaded: bool = false
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _assets: Dictionary = {}


static func draw_terrain(canvas: CanvasItem, rect: Rect2, depth: int) -> bool:
	if not is_instance_valid(canvas) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	# The deepest material continues below the eight authored strata.
	var asset: Dictionary = get_asset("terrain", "rock", "", 1, clampi(depth, 1, 8))
	if asset.is_empty():
		return false
	var texture: Texture2D = asset.texture
	# Terrain files are full standalone textures. UVs are anchored in the world,
	# independent of the visible slice, build mode and camera offset.
	var texels_per_unit: Vector2 = texture.get_size() / TERRAIN_TILE_SIZE
	canvas.draw_texture_rect_region(texture, rect, Rect2(rect.position * texels_per_unit, rect.size * texels_per_unit), TERRAIN_TINT, false, false)
	return true


static func draw_background(canvas: CanvasItem, rect: Rect2, room_id: String, path_id: String = "", tier: int = 1, depth: int = 1, phase_id: String = "base") -> bool:
	if not is_instance_valid(canvas) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var asset: Dictionary = get_asset("background", room_id, path_id, tier, depth, phase_id)
	if asset.is_empty():
		return false
	var region: Rect2 = asset.region
	var fit: float = minf(rect.size.x / region.size.x, rect.size.y / region.size.y)
	var fitted_size: Vector2 = region.size * fit
	var at := Vector2(rect.position.x + (rect.size.x - fitted_size.x) * 0.5, rect.end.y - fitted_size.y)
	canvas.draw_rect(rect, STONE_FILL)
	canvas.draw_texture_rect_region(asset.texture, Rect2(at, fitted_size), region)
	return true


static func draw_actor(canvas: CanvasItem, foot: Vector2, max_size: Vector2, kind: String, id: String, path_id: String = "", tier: int = 1, tint: Color = Color.WHITE, flip_h: bool = false, phase_id: String = "base") -> bool:
	if not is_instance_valid(canvas) or max_size.x <= 0.0 or max_size.y <= 0.0:
		return false
	if kind not in ["hero", "lord", "room"]:
		return false
	var asset: Dictionary = get_asset(kind, id, path_id, tier, 1, phase_id)
	if asset.is_empty():
		return false
	var region: Rect2 = asset.region
	var bounds: Rect2 = asset.bounds
	var pivot: Vector2 = asset.pivot
	var fit: float = minf(max_size.x / bounds.size.x, max_size.y / bounds.size.y)
	# Keep the complete transparent cell. Bounds set its scale, not a new crop.
	# A negative draw width flips UVs without moving the rectangle's left edge.
	var displayed_pivot := Vector2(region.size.x - pivot.x if flip_h else pivot.x, pivot.y)
	var destination := Rect2(foot - displayed_pivot * fit, region.size * fit)
	if flip_h:
		destination.size.x = -destination.size.x
	canvas.draw_texture_rect_region(asset.texture, destination, region, tint)
	return true


## Returns a shared read-only descriptor or {}. Region is in texture pixels;
## bounds (Rect2) and pivot (Vector2) are local to that region/cell.
## Non-base phases require entry.phases[phase_id] containing a complete entry.
static func get_asset(kind: String, id: String, path_id: String = "", tier: int = 1, depth: int = 1, phase_id: String = "base") -> Dictionary:
	_load_manifest()
	var stable_id: String = id
	if kind in ["room", "background"] and not path_id.is_empty() and id not in ["rock", "empty"]:
		stable_id = path_id + (":15" if tier >= 15 else ":5" if tier >= 5 else "")
	var cache_key: String = "%s/%s/%d/%s" % [kind, stable_id, depth, phase_id]
	if _assets.has(cache_key):
		return _assets[cache_key]
	var entry: Dictionary = {}
	match kind:
		"hero":
			entry = _dictionary(_dictionary(_manifest.get("heroes")).get(stable_id))
		"lord":
			entry = _dictionary(_dictionary(_manifest.get("lords")).get(stable_id))
		"room":
			entry = _dictionary(_dictionary(_manifest.get("actors")).get(stable_id))
		"background":
			if id == "rock":
				entry = _terrain_entry(depth, "rock")
			elif id == "empty" and depth != 1:
				entry = _terrain_entry(depth, "empty")
			else:
				entry = _dictionary(_dictionary(_manifest.get("backgrounds")).get(stable_id))
		"terrain":
			entry = _terrain_entry(depth, id)
	var asset: Dictionary = _resolve_phase(entry, stable_id, phase_id)
	if asset.is_empty() and kind == "background" and id == "empty":
		asset = _resolve_phase(_terrain_entry(depth, "empty"), stable_id, phase_id)
	asset.make_read_only()
	_assets[cache_key] = asset
	return asset


static func _load_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	if FileAccess.file_exists(MANIFEST_PATH):
		_manifest = _dictionary(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)))


static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _terrain_entry(depth: int, id: String) -> Dictionary:
	var layer: Dictionary = _dictionary(_dictionary(_manifest.get("terrain")).get(str(depth)))
	return _dictionary(layer.get(id))


static func _resolve_phase(entry: Dictionary, stable_id: String, phase_id: String) -> Dictionary:
	if phase_id != "base":
		entry = _dictionary(_dictionary(entry.get("phases")).get(phase_id))
	if entry.is_empty():
		return {}
	var path: String = str(entry.get("path", ""))
	if path.is_empty():
		var sheet: Dictionary = _dictionary(_dictionary(_manifest.get("sheets")).get(str(entry.get("sheet", ""))))
		path = str(sheet.get("path", ""))
	var texture: Texture2D = _texture(path)
	if texture == null:
		return {}
	var region := Rect2(Vector2.ZERO, texture.get_size())
	if entry.has("cell") or entry.has("region"):
		# Background entries can retain cell metadata beside the actual region.
		var coordinates: Variant = entry.get("region", entry.get("cell"))
		if not _numbers(coordinates, 4):
			return {}
		region = Rect2(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]), float(coordinates[3]))
	if not _inside(region, texture.get_size()):
		return {}
	var bounds := Rect2(Vector2.ZERO, region.size)
	if entry.has("bounds"):
		var coordinates: Variant = entry.bounds
		if not _numbers(coordinates, 4):
			return {}
		var minimum := Vector2(float(coordinates[0]), float(coordinates[1]))
		var maximum := Vector2(float(coordinates[2]), float(coordinates[3]))
		bounds = Rect2(minimum, maximum - minimum)
	if not _inside(bounds, region.size):
		return {}
	var pivot := Vector2(bounds.get_center().x, bounds.end.y)
	if entry.has("pivot"):
		if not _numbers(entry.pivot, 2):
			return {}
		pivot = Vector2(float(entry.pivot[0]), float(entry.pivot[1]))
	return {"texture": texture, "path": path, "region": region, "bounds": bounds, "pivot": pivot, "asset_id": stable_id, "phase_id": phase_id}


static func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		# Cache misses too: unavailable art must not perform disk reads every frame.
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	return _textures[path]


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	return true


static func _inside(rect: Rect2, size: Vector2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0 and rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= size.x and rect.end.y <= size.y
