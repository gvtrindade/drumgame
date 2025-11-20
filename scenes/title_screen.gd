extends Control

@onready var quickplay_button = $VBoxContainer/MarginContainer/VBoxContainer/QuickplayButton


func _ready():
  quickplay_button.grab_focus()
  
  
func _on_quickplay_button_button_down():
  SceneManager.goto_scene("song_select")


func _on_options_button_button_down():
  SceneManager.goto_scene("controller_profile")
  

func _on_quit_button_button_down() -> void:
  get_tree().quit()
