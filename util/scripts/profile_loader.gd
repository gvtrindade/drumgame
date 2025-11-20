class_name ProfileLoader
extends Node

const CONTROLLER_PROFILES_PATH = "user://controller_profiles"


func load_key_bindings():
  var active_profile = _load_active_profile()
  if active_profile.is_empty():
    print("No active profile found, using defaults")
    return
  
  var profile_path = "%s/%s.json" % [CONTROLLER_PROFILES_PATH, active_profile]
  if not FileAccess.file_exists(profile_path):
    print("Profile file not found: ", profile_path)
    return
  
  var file = FileAccess.open(profile_path, FileAccess.READ)
  if file == null:
    print("Failed to open profile file")
    return
  
  var json_string = file.get_as_text()
  file.close()
  
  var json = JSON.new()
  var parse_result = json.parse(json_string)
  
  if parse_result != OK:
    print("Failed to parse profile JSON")
    return
  
  print("Loaded key bindings from profile: ", active_profile)
  return json.data

func _load_active_profile() -> String:
  var settings_path = "user://settings.txt"
  if not FileAccess.file_exists(settings_path):
    print("Settings file not found")
    return ""
  
  var file = FileAccess.open(settings_path, FileAccess.READ)
  if file == null:
    print("Failed to open settings file")
    return ""
  
  var active_profile = file.get_as_text().strip_edges()
  file.close()
  
  return active_profile