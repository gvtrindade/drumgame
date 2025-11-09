extends Control

func _ready():
  # Set focus to first button for keyboard/controller navigation
  $VBoxContainer/MarginContainer/VBoxContainer/QuickplayButton.grab_focus()
  
  # Connect button signals
  $VBoxContainer/MarginContainer/VBoxContainer/QuickplayButton.pressed.connect(_on_quickplay_pressed)
  $VBoxContainer/MarginContainer/VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
  $VBoxContainer/MarginContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_quickplay_pressed():
  # Switch to gameplay scene - adjust path as needed
  SceneManager.goto_scene("song_select")

func _on_options_pressed():
  # Switch to options scene - adjust path as needed
  SceneManager.goto_scene("controller_profile")
  
func _on_quit_pressed():
  get_tree().quit()
