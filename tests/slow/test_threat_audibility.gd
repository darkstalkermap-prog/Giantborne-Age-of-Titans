extends TestSuite
## M6 gate (decision 7; the audio sheet's items 1 and 12: "the off-camera sting cuts through the
## combat layer"): a far threat is heard over the combat music at every growth stage. Measured on the
## shipped files the way the engine plays them: K-weighted momentary loudness (ITU-R BS.1770: 400 ms
## blocks every 100 ms) of the Hollow's combat layer - its stems rendered offline (mix_audio) at the
## set's combat volumes through the Music bus, dual mono as a 2D player plays a mono stem (+3 dB) -
## and of each sting variant at the level the mix gives it at the far threshold (far_m x the distance
## scale) of stages 1-6: its bank volume through the alert class's distances and level floor
## (AudioMath.floored_volume, level_at) and the SFX bus, its energy split over two channels by the 3D
## panner (no +3 dB). The quietest variant's loudest block must come within FULL_BAND_UNDER_DB of the
## combat layer's median block, and in the sting's own band (above BAND_HZ, where the combat drums and
## brass have little) it must stand BAND_OVER_DB above the music. Before the alert class, the sting at
## 20 m was 26 dB under the combat layer and 16 dB under it even in its own band. About 5 s.
## Everything runs at the files' 22.05 kHz (the stems and the threat cues are 22.05 kHz mono).

const RATE := 22050.0
const SET_ID := "music.valley_calm"
const STING := "sfx.threat.sting"
const MIX_ID := "audio_mix.default"
const BAND_HZ := 4000.0
const FULL_BAND_UNDER_DB := 6.0
const BAND_OVER_DB := 3.0
## Growth stage heights (data/growth/growth_0*.json).
const HEIGHTS := [3.6576, 5.49, 7.87, 10.97, 14.63, 18.90]


# --------------------------------------------------------------------------- signals

## A 16-bit PCM WAV master as mono floats (its first channel) and its rate.
static func read_wav(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var rate := 22050
	var channels := 1
	var pos := 12
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if id == "fmt ":
			channels = bytes.decode_u16(pos + 10)
			rate = bytes.decode_u32(pos + 12)
		elif id == "data":
			data = bytes.slice(pos + 8, pos + 8 + size)
			break
		pos += 8 + size + (size % 2)
	var out := PackedFloat32Array()
	var step := 2 * maxi(1, channels)
	out.resize(data.size() / step)
	for i in out.size():
		out[i] = float(data.decode_s16(i * step)) / 32768.0
	return {"rate": rate, "x": out}


## The first `seconds` of a mono stream at its own 22.05 kHz: mix_audio at the 44.1 kHz mix rate with
## a rate scale of 2 steps exactly one source sample per output frame.
static func render(path: String, seconds: float) -> PackedFloat32Array:
	var stream := load(path) as AudioStream
	var pb := stream.instantiate_playback()
	pb.start(0.0)
	var frames := int(seconds * RATE)
	var out := PackedFloat32Array()
	while out.size() < frames:
		var chunk := pb.mix_audio(2.0, mini(8192, frames - out.size()))
		if chunk.is_empty():
			break
		for f in chunk:
			out.append(f.x)
	pb.stop()
	return out


## Biquad coefficients [b0, b1, b2, a1, a2] (a0 = 1) for BS.1770's K-weighting stages and plain
## second-order high-passes (the RBJ forms the standard's filters come from).
static func high_shelf(fc: float, q: float, gain_db: float) -> PackedFloat64Array:
	var a := pow(10.0, gain_db / 40.0)
	var w0 := TAU * fc / RATE
	var alpha := sin(w0) / (2.0 * q)
	var c := cos(w0)
	var sa := 2.0 * sqrt(a) * alpha
	var a0 := (a + 1.0) - (a - 1.0) * c + sa
	return PackedFloat64Array([a * ((a + 1.0) + (a - 1.0) * c + sa) / a0, -2.0 * a * ((a - 1.0) + (a + 1.0) * c) / a0,
		a * ((a + 1.0) + (a - 1.0) * c - sa) / a0, 2.0 * ((a - 1.0) - (a + 1.0) * c) / a0,
		((a + 1.0) - (a - 1.0) * c - sa) / a0])


static func high_pass(fc: float, q: float) -> PackedFloat64Array:
	var w0 := TAU * fc / RATE
	var alpha := sin(w0) / (2.0 * q)
	var c := cos(w0)
	var a0 := 1.0 + alpha
	return PackedFloat64Array([(1.0 + c) / 2.0 / a0, -(1.0 + c) / a0, (1.0 + c) / 2.0 / a0, -2.0 * c / a0, (1.0 - alpha) / a0])


static func filter(x: PackedFloat32Array, k: PackedFloat64Array) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var xi := float(x[i])
		var yi := k[0] * xi + k[1] * x1 + k[2] * x2 - k[3] * y1 - k[4] * y2
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = yi
		y[i] = yi
	return y


static func k_weight(x: PackedFloat32Array) -> PackedFloat32Array:
	return filter(filter(x, high_shelf(1681.974450955533, 0.7071752369554196, 3.999843853973347)),
		high_pass(38.13547087602444, 0.5003270373238773))


## Above BAND_HZ (fourth order): the sting's band.
static func band(x: PackedFloat32Array) -> PackedFloat32Array:
	var k := high_pass(BAND_HZ, 0.7071)
	return filter(filter(x, k), k)


## The loudness of every 400 ms block, 100 ms apart: -0.691 + 10 log10(channels x mean square).
static func blocks(x: PackedFloat32Array, channels: float) -> PackedFloat64Array:
	var n := int(0.4 * RATE)
	var hop := int(0.1 * RATE)
	var out := PackedFloat64Array()
	var start := 0
	while start + n <= x.size():
		var sum := 0.0
		for i in range(start, start + n):
			sum += float(x[i]) * float(x[i])
		out.append(-0.691 + 10.0 * log(maxf(channels * sum / float(n), 1e-20)) / log(10.0))
		start += hop
	return out


static func median(v: PackedFloat64Array) -> float:
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2] if not s.is_empty() else -INF


static func peak(v: PackedFloat64Array) -> float:
	var best := -INF
	for x in v:
		best = maxf(best, x)
	return best


# --------------------------------------------------------------------------- the check

func test_a_far_sting_cuts_through_the_combat_layer_at_every_stage() -> void:
	var mix := GameData.get_record(MIX_ID)
	var music_db := float(mix.bus_db.Music)
	var sfx_db := float(mix.bus_db.SFX)
	# the combat layer as it plays (one melody variant at its combat volume)
	var rec := GameData.get_record(SET_ID)
	var layer: Dictionary = rec.layers.combat
	var first_variant := str((rec.melody.variants as Array)[0])
	var combat := PackedFloat32Array()
	for stem: String in rec.stems:
		var key := "melody" if stem.begins_with("melody_") else stem
		if not layer.has(key) or (key == "melody" and stem != first_variant):
			continue
		var x := render(str(rec.stems[stem]), 30.0)
		var g := db_to_linear(float(layer[key]) + music_db)
		if combat.is_empty():
			combat.resize(x.size())
		for i in mini(x.size(), combat.size()):
			combat[i] += x[i] * g
	assert_true(combat.size() >= int(29.0 * RATE), "the combat layer rendered (%.1f s)" % (combat.size() / RATE))
	var music_full := median(blocks(k_weight(combat), 2.0))
	var music_band := median(blocks(band(combat), 2.0))
	print("    combat layer of %s: momentary median %.1f LUFS, above %d Hz %.1f" % [SET_ID, music_full, int(BAND_HZ), music_band])
	assert_true(music_full > -30.0 and music_full < -12.0, "a plausible combat loudness (%.1f LUFS)" % music_full)
	# every sting variant, padded so its blocks see all of it
	var bank: Dictionary = (GameData.get_record("audio_bank.threat").cues as Dictionary)[STING]
	var volume := float(bank.volume_db)
	var cls: Dictionary = mix.classes[str(bank.get("class", "impact"))]
	var floor_db := float(cls.get("floor_db", -INF))
	var far_m := float(mix.threat.far_m)
	var quietest := INF
	var quietest_band := INF
	for path: String in bank.files:
		var wav := read_wav(path)
		assert_eq(int(wav.rate), int(RATE), "%s is a 22.05 kHz master" % path.get_file())
		var padded := PackedFloat32Array()
		padded.resize(int(0.4 * RATE))
		padded.append_array(wav.x)
		var tail := PackedFloat32Array()
		tail.resize(int(0.4 * RATE))
		padded.append_array(tail)
		quietest = minf(quietest, peak(blocks(k_weight(padded), 1.0)))
		quietest_band = minf(quietest_band, peak(blocks(band(padded), 1.0)))
	for h: float in HEIGHTS:
		var s := AudioMath.distance_scale(h)
		var d := far_m * s
		var dist := AudioMath.class_distances(cls, s, s)
		var played := volume if is_inf(floor_db) else AudioMath.floored_volume(d, dist.x, dist.y, volume, floor_db)
		var gain := AudioMath.level_at(d, dist.x, dist.y, played) + sfx_db
		var full := quietest + gain
		var in_band := quietest_band + gain
		print("    a %.1f m giant: the sting %.0f m away at %.1f LUFS (%.1f dB against the combat layer), above %d Hz %.1f (%+.1f dB)" % [
			h, d, full, full - music_full, int(BAND_HZ), in_band, in_band - music_band])
		assert_true(full >= music_full - FULL_BAND_UNDER_DB,
			"a %.1f m giant hears the sting %.0f m away within %.0f dB of the combat layer (%.1f against %.1f LUFS)" % [
				h, d, FULL_BAND_UNDER_DB, full, music_full])
		assert_true(in_band >= music_band + BAND_OVER_DB,
			"and above it in the sting's band (%.1f against %.1f)" % [in_band, music_band])
