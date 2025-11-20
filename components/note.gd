extends Area2D

var FALL_SPEED = 300  # Will match rhythm_game

@export var NOTE_HEIGHT = 30
@export var NOTE_WIDTH = 80

var column: int = 0
var note_color: Color = Color.RED

@onready var visual = $NoteVisual

func _ready():
  add_to_group("notes")
  _setup_visual()
  _setup_collision()
  # Get fall speed from parent if available
  if get_parent() and get_parent().get_parent():
    var game = get_parent().get_parent()
    if "NOTE_SPEED" in game:
      FALL_SPEED = game.NOTE_SPEED

func _setup_visual():
  visual.size = Vector2(NOTE_WIDTH, NOTE_HEIGHT)
  visual.position = Vector2(-NOTE_WIDTH / 2, -NOTE_HEIGHT / 2)
  visual.color = note_color

func _setup_collision():
  var collision = $NoteCollision
  var rect_shape = RectangleShape2D.new()
  rect_shape.size = Vector2(NOTE_WIDTH, NOTE_HEIGHT)
  collision.shape = rect_shape

func _process(delta):
  position.y += FALL_SPEED * delta
  
  if position.y > 700:
    queue_free()

func set_note_color(color: Color):
  note_color = color
  if visual:
    visual.color = color

func set_column(col: int):
  column = col
