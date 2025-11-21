extends Node2D

class_name TextNotificationManager

# Configuration
var text_duration: float = 2.0 # How long text stays visible (seconds)
var fade_duration: float = 0.5 # How long fade takes (seconds)
var vertical_spacing: float = 40.0 # Distance between stacked texts
var bottom_left_offset: Vector2 = Vector2(20, -40) # Offset from bottom-left corner
var font_size: int = 24
var text_color: Color = Color.WHITE
var font_path: String = "res://path/to/your/font.tres" # Change to your font path

# Internal state
var notification_stack: Array[Dictionary] = []
var container: Node2D
var viewport_size: Vector2

func _ready() -> void:
  viewport_size = get_viewport_rect().size
  # Create a container for all notifications
  container = Node2D.new()
  add_child(container)

func _process(_delta: float) -> void:
  # Update positions and check for expired notifications
  var i = 0
  while i < notification_stack.size():
    var notif = notification_stack[i]
    notif.elapsed_time += _delta
    
    # Check if time to start fading
    if notif.elapsed_time >= notif.duration:
      notif.fade_elapsed += _delta
      # Calculate fade progress (0 to 1)
      var fade_progress = min(notif.fade_elapsed / notif.fade_duration, 1.0)
      notif.label.modulate.a = 1.0 - fade_progress
      
      # Remove when fully faded
      if fade_progress >= 1.0:
        notif.label.queue_free()
        notification_stack.remove_at(i)
        # Shift remaining notifications down
        _shift_notifications_down()
        continue
    
    # Update vertical position based on stack index
    var target_y = viewport_size.y + bottom_left_offset.y - (i * vertical_spacing)
    notif.label.position.y = target_y
    i += 1

## Spawns a new text notification
func spawn_text(text: String, duration: float = -1.0) -> void:
  if duration < 0:
    duration = text_duration
  
  # Create label
  var label = Label.new()
  label.text = text
  label.add_theme_font_size_override("font_size", font_size)
  label.add_theme_color_override("font_color", text_color)
  
  # Load custom font if available
  if ResourceLoader.exists(font_path):
    label.add_theme_font_override("font", load(font_path))
  
  label.position = Vector2(bottom_left_offset.x, viewport_size.y + bottom_left_offset.y)
  label.modulate.a = 1.0
  container.add_child(label)
  
  # Add to stack
  var notification = {
    "label": label,
    "duration": duration,
    "fade_duration": fade_duration,
    "elapsed_time": 0.0,
    "fade_elapsed": 0.0
  }
  notification_stack.append(notification)
  
  # Position the new notification at the top of the stack
  _update_all_positions()

## Shifts all notifications down after one disappears
func _shift_notifications_down() -> void:
  # All notifications above the removed one shift down
  _update_all_positions()

## Updates positions for all notifications in the stack
func _update_all_positions() -> void:
  for i in range(notification_stack.size()):
    var notif = notification_stack[i]
    var target_y = viewport_size.y + bottom_left_offset.y - (i * vertical_spacing)
    # Use a tween for smooth movement during repositioning
    var tween = create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(notif.label, "position:y", target_y, 0.2)

## Helper: Clear all notifications
func clear_all() -> void:
  for notif in notification_stack:
    notif.label.queue_free()
  notification_stack.clear()

## Helper: Set configuration
func configure(duration: float, fade: float, spacing: float, color: Color = Color.WHITE) -> void:
  text_duration = duration
  fade_duration = fade
  vertical_spacing = spacing
  text_color = color
