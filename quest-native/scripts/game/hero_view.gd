class_name HeroView
extends Node3D
## Presentation of the hero. Reads HeroMotor each frame; never changes rules.

signal footstep(surface: String, at: Vector3, strength: float)
signal cloth(at: Vector3, strength: float)

var motor: HeroMotor
var body: Node3D
var shadow: MeshInstance3D
var _gait := 0.0
var _react := ""
var _react_t := 0.0


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var thobe := StandardMaterial3D.new()
	thobe.albedo_color = Color("f3ead8")
	thobe.roughness = 0.95
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("c99a73")
	Kit.add(body, Kit.cylinder(0.16, 0.26, 0.75, 14), thobe, Vector3(0, 0.4, 0))
	Kit.add(body, Kit.sphere(0.24, 14), skin, Vector3(0, 0.98, 0))
	Kit.add(body, Kit.cylinder(0.26, 0.27, 0.18, 14), Kit.mat("cloth_red"), Vector3(0, 1.12, 0))
	Kit.add(body, Kit.torus(0.2, 0.25), Kit.mat("iron"), Vector3(0, 1.2, 0))
	shadow = Kit.add(self, Kit.box(Vector3(1.0, 0.002, 0.8)), Kit.mat("shadow_blob"), Vector3.ZERO, false)


func reset(m: HeroMotor) -> void:
	motor = m
	sync(0.0)


func react(event: String) -> void:
	_react = event
	_react_t = 0.0


func sync(dt: float) -> void:
	if motor == null:
		return
	var y := LevelData.surface_y(motor.state.def, motor.pos.x, motor.pos.y)
	position = Vector3(motor.pos.x, y + 0.07, motor.pos.y)
	rotation.y = motor.yaw
	_gait += dt * motor.speed_now * 4.0
	body.position.y = absf(sin(_gait)) * 0.03
	visible = motor.mode != "finishing" or motor.mode_time < 0.2
	shadow.global_position.y = global_position.y
