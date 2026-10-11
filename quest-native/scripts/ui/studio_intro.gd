class_name StudioIntro
extends Node3D
## Aboden Games studio name, shown once at launch before the board appears:
## "عبودين قيمز" with "ABODEN GAMES" beneath it floats in front of the viewer over
## the real room (mixed reality) or the sky (VR), with a short oud sting, then
## drifts up and fades. No logo and no backdrop. About 3.6 seconds; any trigger or
## the menu button skips it. The text follows the viewer's gaze gently, so it is
## seen wherever the player happens to be looking when the session starts.

signal finished

const DURATION := 3.6
const DISTANCE := 1.6  # metres in front of the viewer

var _t := 0.0
var _done := false
var _skipped := false
var _anchor: Node3D
var _word: Sprite3D
var _sound: AudioStreamPlayer
var _head: Callable  # returns the current head Transform3D
var _level := true


func play(head: Callable, level := true) -> void:
	_head = head
	_level = level
	_anchor = Node3D.new()
	add_child(_anchor)
	_follow(1.0)
	_word = Sprite3D.new()
	_word.texture = load("res://assets/brand/aboden_wordmark.png")
	_word.pixel_size = 0.00075  # about 0.9 m wide
	_word.shaded = false
	_word.double_sided = false
	_word.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_word.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_word.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_word.render_priority = 10
	_word.modulate = Color(1.2, 1.2, 1.2, 0.0)  # offsets the scene tonemapper so the text stays bright
	_anchor.add_child(_word)
	_sound = AudioStreamPlayer.new()
	_sound.stream = load("res://audio/sfx/intro_sting.wav")
	_sound.volume_db = -2.0
	add_child(_sound)
	if not Save.muted:
		_sound.play()
	_update(0.0)


## Keep the text in front of the viewer; k = 1 snaps, small k eases toward it.
func _follow(k: float) -> void:
	var head: Transform3D = _head.call()
	var fwd := -head.basis.z
	if _level:  # headset: keep the text upright at eye height
		fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	var target := head.origin + fwd * DISTANCE
	_anchor.global_position = _anchor.global_position.lerp(target, k) if k < 1.0 else target
	if _anchor.global_position.distance_squared_to(head.origin) > 0.01:
		_anchor.look_at(head.origin, Vector3.UP, true)


static func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _update(t: float) -> void:
	var fade_in := _ease((t - 0.15) / 1.0)
	var fade_out := 1.0 - _ease((t - (DURATION - 0.8)) / 0.8)
	_word.modulate.a = fade_in * fade_out
	# Rises gently into place, then drifts a little further as it fades.
	_word.position.y = lerpf(-0.03, 0.0, fade_in) + (1.0 - fade_out) * 0.02
	_word.scale = Vector3.ONE * lerpf(0.94, 1.0, fade_in)
	if _skipped:
		_sound.volume_db = -2.0 + linear_to_db(maxf(fade_out, 0.001))


func skip() -> void:
	if _done:
		return
	# Jump to the fade-out instead of cutting: smoother on the eyes.
	_skipped = true
	_t = maxf(_t, DURATION - 0.5)


func is_playing() -> bool:
	return not _done


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_follow(1.0 - exp(-3.0 * delta))
	_update(_t)
	if _t >= DURATION:
		_done = true
		finished.emit()
		queue_free()
