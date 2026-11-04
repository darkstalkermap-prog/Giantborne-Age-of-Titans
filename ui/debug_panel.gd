class_name DebugPanel
extends PanelContainer
## F3 debug panel (debug builds only): simulation tick, frame time (avg / p95 / p99), player
## state, stage, resources, attack id, queued action, target, camera, AI state, debris and
## pending hits. Exported release builds never show it.

const SAMPLE_COUNT := 300

var _label: Label
var _frame_ms: Array[float] = []
var _accum := 0.0
var enabled := false


func _ready() -> void:
	add_to_group("hud_debug")
	add_theme_stylebox_override("panel", UiKit.box(Color(0.03, 0.04, 0.05, 0.80), 4))
	position = Vector2(12, 86)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", 12)
	_label.add_theme_font_override("font", SystemFont.new())
	add_child(_label)
	enabled = OS.is_debug_build()
	visible = false


func toggle() -> void:
	if enabled:
		visible = not visible


func frame_stats() -> Dictionary:
	if _frame_ms.is_empty():
		return {"avg": 0.0, "p95": 0.0, "p99": 0.0}
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	return {"avg": total / sorted.size(),
		"p95": sorted[int(floor((sorted.size() - 1) * 0.95))],
		"p99": sorted[int(floor((sorted.size() - 1) * 0.99))]}


func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > SAMPLE_COUNT:
		_frame_ms.pop_front()
	if not visible:
		return
	_accum += delta
	if _accum < 0.1:
		return
	_accum = 0.0
	var fs := frame_stats()
	var lines := PackedStringArray()
	lines.append("tick %d   fps %d   frame ms avg %.1f  p95 %.1f  p99 %.1f" % [Sim.tick,
		Engine.get_frames_per_second(), fs.avg, fs.p95, fs.p99])
	var player := get_tree().get_first_node_in_group("player") as GiantPlayer
	if player != null:
		var d := player.get_debug_info()
		lines.append("PLAYER  %s / %s  action=%s  #%d  t=%d  queued=%s" % [d.state, d.phase,
			d.action if d.action != "" else "-", d.instance, d.elapsed, d.queued if d.queued != "" else "-"])
		lines.append("        stage %d  H %.0f  S %.1f  E %.0f  F %.0f  poise %.0f  iframes=%s  parry=%s" % [
			d.stage, d.health, d.stamina, d.essence, d.fury, d.poise, d.invulnerable, d.parry_window])
		lines.append("        target=%s  camera=%s  sprint=%s  pos=(%.1f, %.1f, %.1f)" % [
			d.target if d.target != "" else "-", d.camera, d.sprinting, d.position.x, d.position.y, d.position.z])
	for e in get_tree().get_nodes_in_group("enemies"):
		var s := e as SoldierEnemy
		if s == null:
			continue
		var a := s.get_debug_info()
		lines.append("%s  AI=%s  combat=%s  action=%s  H %.0f  S %.0f  poise %.0f  guard=%s  token=%s  path_fail=%d" % [
			s.entity.entity_id, a.ai, a.combat, a.action if a.action != "" else "-", a.health, a.stamina,
			a.poise, a.guard, a.token, a.path_failures])
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool
	var debris := pool.active_count() if pool != null else 0
	lines.append("entities %d  debris %d/%d  pending hits %d  world deltas %d" % [Sim.entities().size(),
		debris, DebrisPool.MAX_ACTIVE, Sim.pending_hit_count(), WorldState.deltas.size()])
	_label.text = "\n".join(lines)
