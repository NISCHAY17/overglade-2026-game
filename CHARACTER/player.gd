extends CharacterBody2D

@export var speed := 120
@onready var sprite := $AnimatedSprite2D

func _play_run_animation(dir: Vector2):
	if abs(dir.x) > abs(dir.y):
		if dir.x > 0:
			sprite.play("RUNRIGHT")
		else:
			sprite.play("RUNLEFT")
	else:
		if dir.y > 0:
			sprite.play("RUNFRONT")
		else:
			sprite.play("RUNBACKWARD")
			
func _ready():
	add_to_group("player")

func _physics_process(delta):
	var input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)

	if input != Vector2.ZERO:
		velocity = input.normalized() * speed
		_play_run_animation(input)
	else:
		velocity = Vector2.ZERO
		sprite.play("CALM")

	move_and_slide()
