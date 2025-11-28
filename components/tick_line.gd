extends Node2D


@onready var line = $Line2D

var NOTE_SPEED = 300
var spawn_tick: int = 0
var is_major_beat: bool = false

func _ready():
  add_to_group("tick_lines")
  
  if get_parent() and get_parent().get_parent():
    var game = get_parent().get_parent()
    if "NOTE_SPEED" in game:
      NOTE_SPEED = game.NOTE_SPEED

func _process(delta):
  # Move line down at the same speed as notes
  position.y += NOTE_SPEED * delta
  
  # Remove line if it has passed below the hit zone
  if position.y > 500:  # Adjust based on your HIT_ZONE_Y + buffer
    queue_free()

func setup(tick: int, margin_side: float, column_count: int, column_width: float, spawn_y: float, is_major: bool):
  spawn_tick = tick
  is_major_beat = is_major
  
  # Configure line appearance
  var line_thickness = 2.0 if is_major_beat else 1.0
  var line_color = Color(0.7, 0.7, 0.7, 1.0) if is_major_beat else Color(0.5, 0.5, 0.5, 1.0)
  
  line.width = line_thickness
  line.default_color = line_color
  
  # Set line endpoints
  var game_area_width = column_count * column_width
  line.add_point(Vector2(margin_side, 0))
  line.add_point(Vector2(margin_side + game_area_width, 0))
  
  # Set position
  position = Vector2(0, spawn_y)
