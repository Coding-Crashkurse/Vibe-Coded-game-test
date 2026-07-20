extends Node
## Assets — loads Kenney textures (CC0) and generates procedural fallbacks,
## portraits and effect textures. Everything is cached.

var _cache := {}

func tex(n: String) -> Texture2D:
	if _cache.has(n):
		return _cache[n]
	if n.begins_with("tree_side"):
		return tree_side(2 if n.ends_with("2") else 1)
	var path := "res://assets/img/%s.png" % n
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	if t == null:
		t = _procedural(n)
	_cache[n] = t
	return t

## Side-view tree in the JA1 3/4 look: ground shadow + trunk + crown (64×96)
func tree_side(variant: int) -> Texture2D:
	var key := "tree_side_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(64, 96, false, Image.FORMAT_RGBA8)
	_ellipse(img, 32, 86, 23, 7, Color(0, 0, 0, 0.30))
	img.fill_rect(Rect2i(28, 50, 8, 36), Color(0.33, 0.23, 0.13))
	img.fill_rect(Rect2i(30, 50, 3, 36), Color(0.44, 0.31, 0.18))
	var dark := Color(0.12, 0.29, 0.11)
	var mid := Color(0.17, 0.38, 0.14)
	var light := Color(0.24, 0.47, 0.19)
	if variant == 2:
		dark = Color(0.4, 0.26, 0.08)
		mid = Color(0.55, 0.36, 0.1)
		light = Color(0.66, 0.46, 0.14)
	_fill_circle(img, 32, 34, 26, dark)
	_fill_circle(img, 23, 28, 15, mid)
	_fill_circle(img, 42, 30, 13, mid)
	_fill_circle(img, 30, 21, 11, light)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, col: Color) -> void:
	for y in range(max(0, cy - ry), min(img.get_height(), cy + ry + 1)):
		for x in range(max(0, cx - rx), min(img.get_width(), cx + rx + 1)):
			var dx := float(x - cx) / float(rx)
			var dy := float(y - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col)

## Item icon (40×40) for the inventory & action bar
func item_icon(id: String) -> Texture2D:
	var key := "icon_" + id
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	var steel := Color(0.42, 0.45, 0.5)
	var dark := Color(0.15, 0.16, 0.19)
	var wood := Color(0.48, 0.32, 0.16)
	match id:
		"p9":
			img.fill_rect(Rect2i(4, 14, 26, 7), steel)
			img.fill_rect(Rect2i(4, 14, 26, 2), dark)
			img.fill_rect(Rect2i(21, 21, 8, 13), dark)
			img.fill_rect(Rect2i(13, 21, 6, 4), steel)
		"k45":
			img.fill_rect(Rect2i(4, 13, 28, 8), Color(0.32, 0.3, 0.28))
			img.fill_rect(Rect2i(4, 13, 28, 2), dark)
			img.fill_rect(Rect2i(23, 21, 9, 14), wood)
			img.fill_rect(Rect2i(14, 21, 6, 4), dark)
		"flinte", "drachenmaul":
			img.fill_rect(Rect2i(2, 16, 31, 4), steel)
			img.fill_rect(Rect2i(27, 18, 11, 7), wood)
			img.fill_rect(Rect2i(34, 24, 5, 8), wood)
			img.fill_rect(Rect2i(12, 20, 9, 4), wood)
			if id == "drachenmaul":
				img.fill_rect(Rect2i(2, 15, 31, 1), Color(0.82, 0.66, 0.2))
		"svd":
			# Dragunov silhouette: long barrel, telescopic sight, wooden skeleton stock
			img.fill_rect(Rect2i(0, 18, 4, 4), dark)            # flash hider
			img.fill_rect(Rect2i(4, 19, 10, 2), steel)          # barrel
			img.fill_rect(Rect2i(14, 18, 8, 4), wood)           # handguard
			img.fill_rect(Rect2i(14, 18, 8, 1), dark)
			img.fill_rect(Rect2i(22, 17, 8, 6), steel)          # receiver
			img.fill_rect(Rect2i(22, 17, 8, 1), dark)
			img.fill_rect(Rect2i(17, 12, 12, 3), dark)          # telescopic sight
			img.fill_rect(Rect2i(15, 11, 2, 5), steel)          # eyepiece
			img.fill_rect(Rect2i(29, 11, 2, 5), steel)          # objective lens
			img.fill_rect(Rect2i(23, 15, 2, 2), dark)           # scope mount
			img.fill_rect(Rect2i(24, 23, 4, 5), dark)           # magazine
			img.fill_rect(Rect2i(25, 27, 4, 2), dark)           #  (slightly curved)
			img.fill_rect(Rect2i(30, 23, 3, 6), wood)           # pistol grip
			img.fill_rect(Rect2i(30, 17, 10, 3), wood)          # stock upper rail
			img.fill_rect(Rect2i(33, 23, 5, 2), wood)           # stock lower rail
			img.fill_rect(Rect2i(37, 17, 3, 12), wood)          # butt plate
		"mag_9mm":
			img.fill_rect(Rect2i(15, 8, 10, 25), steel)
			img.fill_rect(Rect2i(15, 8, 10, 3), dark)
			img.fill_rect(Rect2i(17, 4, 6, 4), Color(0.75, 0.55, 0.25))
		"mag_45":
			img.fill_rect(Rect2i(14, 10, 12, 22), Color(0.52, 0.44, 0.32))
			img.fill_rect(Rect2i(14, 10, 12, 3), dark)
			img.fill_rect(Rect2i(16, 6, 8, 4), Color(0.75, 0.55, 0.25))
		"mag_schrot":
			img.fill_rect(Rect2i(7, 12, 26, 18), Color(0.5, 0.18, 0.13))
			img.fill_rect(Rect2i(7, 12, 26, 3), Color(0.32, 0.1, 0.08))
			for k in 3:
				img.fill_rect(Rect2i(11 + k * 7, 17, 5, 9), Color(0.85, 0.25, 0.18))
				img.fill_rect(Rect2i(11 + k * 7, 24, 5, 3), Color(0.8, 0.65, 0.25))
		"mag_762":
			img.fill_rect(Rect2i(14, 8, 9, 12), steel)
			img.fill_rect(Rect2i(16, 20, 9, 12), steel)   # curvature suggested
			img.fill_rect(Rect2i(14, 8, 9, 3), dark)
			img.fill_rect(Rect2i(16, 4, 5, 4), Color(0.75, 0.55, 0.25))
		"granate":
			_fill_circle(img, 18, 23, 10, Color(0.19, 0.29, 0.15))
			_fill_circle(img, 15, 20, 4, Color(0.28, 0.4, 0.22))
			img.fill_rect(Rect2i(24, 11, 5, 9), steel)
			_fill_circle(img, 30, 9, 4, steel)
			_fill_circle(img, 30, 9, 2, Color(0, 0, 0, 0))
		"medkit":
			img.fill_rect(Rect2i(5, 10, 30, 23), Color(0.92, 0.9, 0.86))
			img.fill_rect(Rect2i(5, 10, 30, 2), Color(0.6, 0.58, 0.55))
			img.fill_rect(Rect2i(17, 14, 6, 15), Color(0.8, 0.15, 0.12))
			img.fill_rect(Rect2i(12, 18, 16, 6), Color(0.8, 0.15, 0.12))
		_:
			img.fill_rect(Rect2i(8, 8, 24, 24), Color(0.5, 0.45, 0.35))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

## Soft circle texture (muzzle flash, explosion, radius indicators)
func circle(radius: int, col: Color, soft: bool = true) -> Texture2D:
	var key := "circle_%d_%s_%s" % [radius, col.to_html(), soft]
	if _cache.has(key):
		return _cache[key]
	var s := radius * 2 + 2
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / float(radius)
			if d <= 1.0:
				var a := 1.0
				if soft:
					a = clampf(1.0 - d * d, 0.0, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

## Portrait: a real avatar image (assets/textures/portraits/<id>.png) when
## present, otherwise procedural 64x64 from parameters (see Db.MERCS).
func portrait(p: Dictionary) -> Texture2D:
	var key := "por_" + str(p)
	if _cache.has(key):
		return _cache[key]
	if p.has("id"):
		var path := "res://assets/textures/portraits/%s.png" % str(p["id"])
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				_cache[key] = tex
				return tex
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.15, 0.17, 0.10))
	# background vignette
	img.fill_rect(Rect2i(0, 0, 64, 3), Color(0.10, 0.11, 0.06))
	img.fill_rect(Rect2i(0, 61, 64, 3), Color(0.10, 0.11, 0.06))
	var skin: Color = p["skin"]
	var hair: Color = p["hair"]
	var cloth: Color = p["cloth"]
	# shoulders
	img.fill_rect(Rect2i(12, 52, 40, 12), cloth)
	img.fill_rect(Rect2i(16, 48, 32, 6), cloth.darkened(0.15))
	# neck + head
	img.fill_rect(Rect2i(28, 44, 8, 6), skin.darkened(0.1))
	_fill_circle(img, 32, 31, 15, skin)
	# hair
	match int(p["style"]):
		1:
			img.fill_rect(Rect2i(19, 14, 26, 8), hair)
		2:
			img.fill_rect(Rect2i(17, 13, 30, 10), hair)
			img.fill_rect(Rect2i(16, 20, 5, 16), hair)
			img.fill_rect(Rect2i(43, 20, 5, 16), hair)
		3:
			img.fill_rect(Rect2i(29, 7, 6, 16), hair)
		_:
			pass
	# cap / beret
	if p.get("cap") != null:
		var capc: Color = p["cap"]
		img.fill_rect(Rect2i(17, 11, 30, 9), capc)
		img.fill_rect(Rect2i(15, 18, 34, 3), capc.darkened(0.25))
		img.set_pixel(24, 15, Color(0.95, 0.85, 0.4))
		img.set_pixel(25, 15, Color(0.95, 0.85, 0.4))
	# eyes / sunglasses
	if p["shades"]:
		img.fill_rect(Rect2i(21, 27, 22, 5), Color(0.05, 0.05, 0.06))
		img.fill_rect(Rect2i(19, 27, 2, 2), Color(0.05, 0.05, 0.06))
		img.fill_rect(Rect2i(43, 27, 2, 2), Color(0.05, 0.05, 0.06))
	else:
		img.fill_rect(Rect2i(24, 28, 3, 3), Color(0.12, 0.1, 0.08))
		img.fill_rect(Rect2i(37, 28, 3, 3), Color(0.12, 0.1, 0.08))
	# Bart / Mund
	if p["beard"]:
		img.fill_rect(Rect2i(24, 38, 16, 8), hair.darkened(0.1))
	else:
		img.fill_rect(Rect2i(28, 41, 8, 2), skin.darkened(0.45))
	# Rahmen
	var edge := Color(0.42, 0.45, 0.27)
	img.fill_rect(Rect2i(0, 0, 64, 1), edge)
	img.fill_rect(Rect2i(0, 63, 64, 1), edge)
	img.fill_rect(Rect2i(0, 0, 1, 64), edge)
	img.fill_rect(Rect2i(63, 0, 1, 64), edge)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

# ------------------------------------------------------------------ intern

func _fill_circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(max(0, cy - r), min(img.get_height(), cy + r + 1)):
		for x in range(max(0, cx - r), min(img.get_width(), cx + r + 1)):
			if Vector2(x - cx, y - cy).length() <= r:
				img.set_pixel(x, y, col)

## Fallback in case a PNG is missing — the game runs entirely without assets too.
func _procedural(n: String) -> Texture2D:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n)
	if n.begins_with("grass"):
		_noise_fill(img, rng, Color(0.24, 0.45, 0.22), 0.05)
	elif n.begins_with("dirt"):
		_noise_fill(img, rng, Color(0.5, 0.38, 0.24), 0.05)
	elif n.begins_with("water"):
		_noise_fill(img, rng, Color(0.2, 0.4, 0.65), 0.04)
	elif n.begins_with("floor_wood"):
		_noise_fill(img, rng, Color(0.55, 0.4, 0.26), 0.03)
		for y in range(0, 64, 16):
			img.fill_rect(Rect2i(0, y, 64, 1), Color(0.4, 0.28, 0.18))
	elif n.begins_with("floor"):
		_noise_fill(img, rng, Color(0.62, 0.65, 0.66), 0.03)
	elif n.begins_with("carpet"):
		img.fill(Color(0.55, 0.15, 0.12))
		img.fill_rect(Rect2i(0, 0, 64, 4), Color(0.75, 0.6, 0.25))
		img.fill_rect(Rect2i(0, 60, 64, 4), Color(0.75, 0.6, 0.25))
	elif n.begins_with("wall"):
		img.fill(Color(0.45, 0.3, 0.24))
		for y in range(0, 64, 16):
			img.fill_rect(Rect2i(0, y, 64, 2), Color(0.3, 0.2, 0.16))
	elif n.begins_with("tree") or n.begins_with("bush"):
		_circle_into(img, 32, 32, 28, Color(0.16, 0.35, 0.14))
		_circle_into(img, 26, 26, 10, Color(0.22, 0.45, 0.2))
	elif n.begins_with("rock"):
		_circle_into(img, 32, 34, 18, Color(0.5, 0.5, 0.52))
	elif n.begins_with("crate"):
		img.fill_rect(Rect2i(8, 8, 48, 48), Color(0.6, 0.44, 0.24))
		img.fill_rect(Rect2i(8, 8, 48, 4), Color(0.45, 0.32, 0.18))
		img.fill_rect(Rect2i(8, 52, 48, 4), Color(0.45, 0.32, 0.18))
	elif n.begins_with("sandbag"):
		img.fill_rect(Rect2i(4, 20, 56, 24), Color(0.72, 0.66, 0.45))
	elif n.begins_with("window"):
		img.fill_rect(Rect2i(26, 2, 12, 60), Color(0.7, 0.85, 0.95, 0.9))
	elif n.begins_with("well"):
		_circle_into(img, 32, 32, 26, Color(0.4, 0.4, 0.42))
		_circle_into(img, 32, 32, 14, Color(0.15, 0.25, 0.4))
	elif n.begins_with("splat"):
		for i in 14:
			_circle_into(img, rng.randi_range(12, 52), rng.randi_range(12, 52), rng.randi_range(3, 9), Color(0.4, 0.38, 0.36))
	elif n.begins_with("debris"):
		for i in 8:
			img.fill_rect(Rect2i(rng.randi_range(8, 48), rng.randi_range(8, 48), 6, 4), Color(0.55, 0.4, 0.22))
	elif n.contains("_gun") or n.contains("_machine") or n.contains("_stand"):
		# top-down figure: body circle + weapon pointing right
		var body := Color.from_hsv(fmod(abs(float(hash(n))) / 1000.0, 1.0), 0.5, 0.75)
		if not n.contains("_stand"):
			img.fill_rect(Rect2i(34, 28, 26, 8), Color(0.2, 0.2, 0.22))
		_circle_into(img, 28, 32, 15, body)
		_circle_into(img, 28, 32, 8, body.darkened(0.3))
	else:
		img.fill(Color(0.9, 0.2, 0.9))
		img.fill_rect(Rect2i(0, 0, 32, 32), Color(0.1, 0.1, 0.1))
		img.fill_rect(Rect2i(32, 32, 32, 32), Color(0.1, 0.1, 0.1))
	return ImageTexture.create_from_image(img)

func _noise_fill(img: Image, rng: RandomNumberGenerator, base: Color, amount: float) -> void:
	img.fill(base)
	for i in 260:
		var c := base.lightened(rng.randf_range(-amount, amount) * 4.0)
		img.fill_rect(Rect2i(rng.randi_range(0, 60), rng.randi_range(0, 60), rng.randi_range(2, 5), rng.randi_range(2, 5)), c)

func _circle_into(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	_fill_circle(img, cx, cy, r, col)
