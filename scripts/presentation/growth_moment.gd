class_name GrowthMoment
extends Node
## D3: the growth as an event (presentation only; nothing in the simulation reads it). The growth itself is applied
## in one tick (PlayerGrowth: the capsule, the numbers, the camera's zoom fraction); this shows it: the giant's
## visual (its rig, $Visual) swells from its old size to the new over a few seconds instead of popping, the camera
## shakes as he swells and once more as the body settles to its new weight, and the ground's dust rises in a ring
## round his feet. The camera's arm already grows out at its own speed (CameraRig never snaps it), so the world
## falls away below as he rises. Bigger growths last longer: a colossus's (stages 7-9) is the longest.
##
## PlayerGrowth starts one for a growth at a stone (not the debug keys, not a save's restore). The rig's own body
## scale is the new stage's at once (every rig length reads it); only the rig node's uniform scale moves.

## Seconds of the swell for a growth to `stage`: 1.6 s at stage 2 rising to 3.4 s at stage 9.
static func duration_s(stage: int) -> float:
	return clampf(1.35 + 0.23 * float(stage), 1.6, 3.6)


## The swell's shape over t in 0..1: an ease in and out with a little give at the end (the body's weight settling).
static func swell_curve(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	var s := x * x * (3.0 - 2.0 * x)
	return s + 0.035 * sin(x * PI) * x


var player: GiantPlayer = null
var from_scale := 1.0
var seconds := 2.0
var elapsed := 0.0
var stage := 1
var settled := false
## The dust rings raised and the camera shakes asked (tests, the evidence's log).
var dust_raised := 0
var shakes := 0
var _next_shake := 0.0


## Starts the moment on `p` for a growth from body scale `k_old` to `k_new` at `new_stage`. Returns the node.
static func begin(p: GiantPlayer, k_old: float, k_new: float, new_stage: int) -> GrowthMoment:
	if p == null or p.rig == null or k_new <= 0.0:
		return null
	var old := p.get_node_or_null("GrowthMoment") as GrowthMoment
	if old != null:
		old.finish()
		old.name = "GrowthMomentDone"
		old.queue_free()
	var m := GrowthMoment.new()
	m.name = "GrowthMoment"
	m.player = p
	m.from_scale = clampf(k_old / k_new, 0.05, 1.0)
	m.stage = new_stage
	m.seconds = duration_s(new_stage)
	p.add_child(m)
	m._apply(0.0)
	m._dust(0.55)
	return m


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.rig == null:
		queue_free()
		return
	elapsed += delta
	var t := elapsed / maxf(seconds, 0.01)
	_apply(t)
	if player.camera_rig != null and elapsed >= _next_shake and t < 1.0:
		# a low tremor while he swells, stronger for a colossus
		player.camera_rig.add_shake(0.05 + 0.02 * float(maxi(stage - 5, 0)))
		shakes += 1
		_next_shake = elapsed + 0.25
	if t >= 1.0:
		finish()
		queue_free()


## Ends the swell at the new size (the body settles: one last shake and the dust ring at its feet).
func finish() -> void:
	if settled:
		return
	settled = true
	if player != null and is_instance_valid(player) and player.rig != null:
		player.rig.scale = Vector3.ONE
		if player.camera_rig != null:
			player.camera_rig.view_scale = 1.0
			player.camera_rig.add_shake(0.18 + 0.05 * float(maxi(stage - 5, 0)))
			shakes += 1
		_dust(1.0)


func _apply(t: float) -> void:
	var s := lerpf(from_scale, 1.0, swell_curve(t))
	player.rig.scale = Vector3.ONE * maxf(s, 0.01)
	if player.camera_rig != null:
		player.camera_rig.view_scale = minf(s, 1.0) if t < 1.0 else 1.0


## A ring of ground dust round his feet, `f` of the full growth's (the first puff small, the settle's full).
func _dust(f: float) -> void:
	if not player.is_inside_tree():
		return
	var h := float(player.profile.get("height_m", 3.6576))
	var r := float(player.profile.get("capsule_radius_m", 0.85)) * 1.4
	var n := 8
	for i in n:
		var a := TAU * float(i) / float(n)
		var at := player.global_position + Vector3(cos(a) * r, 0.2, sin(a) * r)
		if DustBurst.puff(player, at, h * 0.22 * f, 10, h * 0.12 * f) != null:
			dust_raised += 1
