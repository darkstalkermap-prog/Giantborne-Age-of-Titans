extends TestSuite
## Gate B (the M12 review's finding 7): the creator's picture cache keeps at most ThumbnailCache.MAX_PICTURES, the
## least recently shown going first (it kept every picture for the screen's life: a player browsing the dyes added a
## full set at each). Nothing is drawn here: pictures are stored as the cache stores a drawn one. The garment's key by
## its one dye is in tests/slow/test_creator_thumbnails.gd.

var _cache: ThumbnailCache


func after_each() -> void:
	if is_instance_valid(_cache):
		_cache.free()
	_cache = null


func _item(i: int) -> Dictionary:
	var key := "garment.test_%d|skin.test|dye.test" % i
	return {"id": "garment.test_%d" % i, "key": key, "sized_key": "%s@%d" % [key, ThumbnailCache.SIZE]}


func test_the_cache_keeps_the_most_recently_shown_pictures_only() -> void:
	_cache = ThumbnailCache.new()
	_cache.enabled = true
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var n := ThumbnailCache.MAX_PICTURES
	for i in n:
		_cache._store(_item(i), tex)
	assert_eq(_cache.textures.size(), n, "%d kept" % n)
	_cache.request([_item(0)])   # the oldest shown again: now the newest
	assert_true(_cache.queue.is_empty(), "a cached picture is handed back, not made again")
	for i in range(n, n + 5):
		_cache._store(_item(i), tex)
	assert_eq(_cache.textures.size(), n, "never more than %d" % n)
	assert_true(_cache.cached(str(_item(0).sized_key)) != null, "the picture shown again is kept")
	for i in range(1, 6):
		assert_true(_cache.cached(str(_item(i).sized_key)) == null, "the least recently shown went (%d)" % i)
	assert_true(_cache.cached(str(_item(6).sized_key)) != null, "the next is kept")
	assert_true(_cache.cached(str(_item(n + 4).sized_key)) != null, "the newest is kept")
