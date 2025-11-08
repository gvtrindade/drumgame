extends Control

@onready var device_dropdown: OptionButton = $VBoxContainer/HBoxContainer/DeviceDropdown
@onready var refresh_button: Button = $VBoxContainer/HBoxContainer/RefreshButton
@onready var column_mapping_container: VBoxContainer = $VBoxContainer/ColumnMappingContainer
@onready var input_mapping_panel: Panel = $InputMappingPanel
@onready var modal_label: Label = $InputMappingPanel/VBoxContainer/Label

# ButtonContainer
@onready var save_button: Button = $VBoxContainer/ButtonContainer/SaveButton
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton
@onready var set_active_button: Button = $VBoxContainer/ButtonContainer/SetActiveButton
@onready var profile_line_edit: LineEdit = $VBoxContainer/ButtonContainer/ProfileInputContainer/ProfileLineEdit
@onready var profile_dropdown_button: Button = $VBoxContainer/ButtonContainer/ProfileInputContainer/ProfileDropdownButton
@onready var profile_popup_menu: PopupMenu = PopupMenu.new()

var current_mapping_column: int = -1
var selected_device_id: int = -1
var selected_device_type: String = ""  # "joystick", "midi", or "keyboard"
var column_mappings: Array = []
var is_listening_for_input: bool = false
var loaded_profiles: Array = []
const SETTINGS_FILE_PATH = "user://settings.txt"
var current_active_profile: String = ""


# Drum column names
var column_names: Array = [
  "Left Cymbal", "Hi-Hat", "Left Pedal", "Snare", "High Tom", "Kick", "Low Tom", 
  "Floor Tom", "Cymbal", "Ride"
]

func _ready() -> void:
  # Initialize MIDI support
  OS.open_midi_inputs()
  
  # Set process mode to always process input
  set_process_input(true)
  set_process_unhandled_input(true)
  
  setup_device_dropdown()
  setup_column_list()
  setup_input_modal()
  setup_refresh_button()
  setup_bottom_buttons()
  
  # Initialize mappings array
  for i in range(10):
    column_mappings.append([])
  
  # Load saved profiles into dropdown
  load_profiles_list()
  
  # Load active profile if exists
  load_active_profile()

func setup_refresh_button() -> void:
  refresh_button.text = "Refresh Devices"
  refresh_button.pressed.connect(_on_refresh_devices_pressed)

func setup_device_dropdown() -> void:
  device_dropdown.clear()
  
  device_dropdown.add_item("Select a device...", -1)
  device_dropdown.add_separator()
  
  # Add Keyboard option (always available)
  device_dropdown.add_item("=== Keyboard ===", -2)
  device_dropdown.set_item_disabled(device_dropdown.item_count - 1, true)
  device_dropdown.add_item("  Computer Keyboard", 0)
  device_dropdown.set_item_metadata(device_dropdown.item_count - 1, "keyboard")
  
  # Add HID/Joystick devices
  var connected_joypads = Input.get_connected_joypads()
  if connected_joypads.size() > 0:
    device_dropdown.add_separator()
    device_dropdown.add_item("=== HID Controllers ===", -3)
    device_dropdown.set_item_disabled(device_dropdown.item_count - 1, true)
    
    for device_id in connected_joypads:
      var device_name = Input.get_joy_name(device_id)
      device_dropdown.add_item("  " + device_name, device_id + 100)  # Offset to avoid conflicts
      device_dropdown.set_item_metadata(device_dropdown.item_count - 1, "joystick")
  
  # Add MIDI devices
  var connected_midi = OS.get_connected_midi_inputs()
  if connected_midi.size() > 0:
    device_dropdown.add_separator()
    device_dropdown.add_item("=== MIDI Devices ===", -4)
    device_dropdown.set_item_disabled(device_dropdown.item_count - 1, true)
    
    for i in range(connected_midi.size()):
      var midi_name = connected_midi[i]
      device_dropdown.add_item("  " + midi_name, i + 1000)  # Offset MIDI IDs
      device_dropdown.set_item_metadata(device_dropdown.item_count - 1, "midi")
  
  device_dropdown.item_selected.connect(_on_device_selected)

func _on_refresh_devices_pressed() -> void:
  # Reopen MIDI inputs to detect new devices
  OS.close_midi_inputs()
  OS.open_midi_inputs()
  
  # Store current selection
  var previous_device_id = selected_device_id
  var previous_device_type = selected_device_type
  
  # Rebuild dropdown
  device_dropdown.item_selected.disconnect(_on_device_selected)
  setup_device_dropdown()
  
  # Try to restore previous selection
  if previous_device_id != -1:
    for i in range(device_dropdown.item_count):
      if device_dropdown.get_item_id(i) == previous_device_id:
        var metadata = device_dropdown.get_item_metadata(i)
        if metadata == previous_device_type:
          device_dropdown.select(i)
          break
  
  print("Device list refreshed. Found Keyboard, ", Input.get_connected_joypads().size(), 
      " HID devices, and ", OS.get_connected_midi_inputs().size(), " MIDI devices")

func setup_column_list() -> void:
  for i in range(10):
    var column_item = create_column_item(i, column_names[i])
    column_mapping_container.add_child(column_item)

func create_column_item(column_index: int, column_name: String) -> HBoxContainer:
  var hbox = HBoxContainer.new()
  
  # Column label
  var label = Label.new()
  label.text = column_name
  label.custom_minimum_size.x = 100
  hbox.add_child(label)
  
  # Mapped inputs display
  var inputs_label = Label.new()
  inputs_label.name = "InputsLabel"
  inputs_label.text = "No inputs mapped"
  inputs_label.custom_minimum_size.x = 300
  hbox.add_child(inputs_label)
  
  # Add input button
  var add_button = Button.new()
  add_button.text = "Add Input"
  add_button.pressed.connect(_on_add_input_pressed.bind(column_index))
  hbox.add_child(add_button)
  
  # Add reset button
  var reset_button = Button.new()
  reset_button.text = "Reset"
  reset_button.pressed.connect(clear_column_mappings.bind(column_index))
  hbox.add_child(reset_button)
  
  return hbox

func setup_input_modal() -> void:
  input_mapping_panel.visible = false
  input_mapping_panel.size = Vector2(400, 200)
  input_mapping_panel.anchors_preset = Control.PRESET_CENTER
  
  var cancel_button = input_mapping_panel.get_node("VBoxContainer/CancelButton")
  cancel_button.pressed.connect(_on_modal_cancel)
  

func _on_device_selected(index: int) -> void:
  var item_id = device_dropdown.get_item_id(index)
  var metadata = device_dropdown.get_item_metadata(index)
  
  if item_id < 0 or metadata == null:
    selected_device_id = -1
    selected_device_type = ""
  else:
    # Check if device is actually changing
    var new_device_id = item_id
    var new_device_type = str(metadata)
    
    if new_device_id != selected_device_id or new_device_type != selected_device_type:
      # Device changed - clear all mappings
      clear_all_mappings()
      
      selected_device_id = new_device_id
      selected_device_type = new_device_type
      
      match selected_device_type:
        "keyboard":
          print("Selected device: Computer Keyboard")
        "joystick":
          var joy_id = item_id - 100
          print("Selected HID device: ", Input.get_joy_name(joy_id))
        "midi":
          var midi_devices = OS.get_connected_midi_inputs()
          var midi_index = item_id - 1000
          if midi_index < midi_devices.size():
            print("Selected MIDI device: ", midi_devices[midi_index])
      
      print("Cleared all mappings due to device change")


func clear_all_mappings() -> void:
  for i in range(column_mappings.size()):
    clear_column_mappings(i)
    
    
func clear_column_mappings(i: int) -> void:
  column_mappings[i].clear()
  update_column_display(i)


func _on_add_input_pressed(column_index: int) -> void:
  if selected_device_id == -1:
    push_warning("Please select a device first!")
    return
  
  current_mapping_column = column_index
  is_listening_for_input = true
  
  var device_type_text = ""
  match selected_device_type:
    "keyboard":
      device_type_text = "keyboard"
    "joystick":
      device_type_text = "controller"
    "midi":
      device_type_text = "MIDI device"
  
  modal_label.text = "Press any button/key on your " + device_type_text + " to map to:\n" + column_names[column_index]
  input_mapping_panel.visible = true
  input_mapping_panel.position = (get_viewport_rect().size - input_mapping_panel.size) / 2
  

# Use _input for catching events before they're blocked by modal
func _input(event: InputEvent) -> void:
  if not is_listening_for_input or current_mapping_column == -1:
    return
  
  # Handle Keyboard input
  if selected_device_type == "keyboard":
    if event is InputEventKey and event.pressed and not event.echo:
      var key_name = OS.get_keycode_string(event.physical_keycode)
      add_mapping(current_mapping_column, {
        "type": "keyboard", 
        "keycode": event.physical_keycode,
        "key_name": key_name
      })
      get_viewport().set_input_as_handled()
      close_modal()
      return
  
  # Handle HID/Joystick input
  elif selected_device_type == "joystick":
    var joy_id = selected_device_id - 100
    
    if event is InputEventJoypadButton and event.device == joy_id and event.pressed:
      add_mapping(current_mapping_column, {
        "type": "joystick_button", 
        "button": event.button_index,
        "device": joy_id
      })
      get_viewport().set_input_as_handled()
      close_modal()
      return
    
    elif event is InputEventJoypadMotion and event.device == joy_id:
      if abs(event.axis_value) > 0.5:
        add_mapping(current_mapping_column, {
          "type": "joystick_axis", 
          "axis": event.axis, 
          "direction": sign(event.axis_value),
          "device": joy_id
        })
        get_viewport().set_input_as_handled()
        close_modal()
        return
  
  # Handle MIDI input
  elif selected_device_type == "midi":
    if event is InputEventMIDI:
      # Map MIDI note on messages (message type 9)
      if event.message == MIDI_MESSAGE_NOTE_ON:
        add_mapping(current_mapping_column, {
          "type": "midi_note", 
          "note": event.pitch, 
          "channel": event.channel
        })
        get_viewport().set_input_as_handled()
        close_modal()
        return
      
      # Map MIDI control change messages
      elif event.message == MIDI_MESSAGE_CONTROL_CHANGE:
        add_mapping(current_mapping_column, {
          "type": "midi_cc", 
          "controller": event.controller_number, 
          "channel": event.channel
        })
        get_viewport().set_input_as_handled()
        close_modal()
        return

func add_mapping(column_index: int, mapping_data: Dictionary) -> void:
  column_mappings[column_index].append(mapping_data)
  update_column_display(column_index)
  
  print("Mapped ", mapping_data, " to column ", column_names[column_index])

func update_column_display(column_index: int) -> void:
  var column_item = column_mapping_container.get_child(column_index)
  var inputs_label = column_item.get_node("InputsLabel")
  
  if column_mappings[column_index].is_empty():
    inputs_label.text = "No inputs mapped"
  else:
    var mapped_inputs = []
    for input_data in column_mappings[column_index]:
      var input_type = input_data.get("type", "")
      
      match input_type:
        "keyboard":
          mapped_inputs.append(input_data.key_name)
        "joystick_button":
          mapped_inputs.append("Button " + str(input_data.button))
        "joystick_axis":
          var dir_text = "+" if input_data.direction > 0 else "-"
          mapped_inputs.append("Axis " + str(input_data.axis) + dir_text)
        "midi_note":
          mapped_inputs.append("Note " + str(input_data.note) + " (Ch" + str(input_data.channel) + ")")
        "midi_cc":
          mapped_inputs.append("CC " + str(input_data.controller) + " (Ch" + str(input_data.channel) + ")")
    
    inputs_label.text = ", ".join(mapped_inputs)

func close_modal() -> void:
  is_listening_for_input = false
  current_mapping_column = -1
  input_mapping_panel.visible = false

func _on_modal_cancel() -> void:
  close_modal()

func get_column_mappings() -> Array:
  return column_mappings

func save_profile(profile_name: String) -> void:
  var device_name = ""
  match selected_device_type:
    "keyboard":
      device_name = "Computer Keyboard"
    "joystick":
      var joy_id = selected_device_id - 100
      device_name = Input.get_joy_name(joy_id)
    "midi":
      var midi_devices = OS.get_connected_midi_inputs()
      var midi_index = selected_device_id - 1000
      if midi_index < midi_devices.size():
        device_name = midi_devices[midi_index]
  
  var profile_data = {
    "device_id": selected_device_id,
    "device_type": selected_device_type,
    "device_name": device_name,
    "mappings": column_mappings
  }
  
  var dir = DirAccess.open("user://")
  if not dir.dir_exists("controller_profiles"):
    dir.make_dir("controller_profiles")
  
  var file = FileAccess.open("user://controller_profiles/" + profile_name + ".json", FileAccess.WRITE)
  file.store_string(JSON.stringify(profile_data))
  file.close()

func setup_bottom_buttons() -> void:
  # Setup profile input with dropdown
  profile_line_edit.placeholder_text = "Profile name..."
  profile_line_edit.custom_minimum_size.x = 200
  profile_line_edit.text_changed.connect(_on_profile_text_changed)
  
  # Setup dropdown button
  profile_dropdown_button.text = "▼"
  profile_dropdown_button.custom_minimum_size.x = 30
  profile_dropdown_button.pressed.connect(_on_profile_dropdown_pressed)
  
  # Setup popup menu
  add_child(profile_popup_menu)
  profile_popup_menu.id_pressed.connect(_on_profile_popup_selected)
  
  # Setup save button
  save_button.text = "Save Profile"
  save_button.pressed.connect(_on_save_button_pressed)
  
  # Setup set active button (if not already created)
  set_active_button.text = "Set as Active"
  set_active_button.pressed.connect(_on_set_active_pressed)
  
  # Setup back button
  back_button.text = "Back"
  back_button.pressed.connect(_on_back_button_pressed)


func _on_save_button_pressed() -> void:
  var profile_name = profile_line_edit.text.strip_edges()
  var original_name = ""
  
  if profile_name.is_empty():
    push_warning("Please enter a profile name!")
    return
  
  if selected_device_id == -1:
    push_warning("Please select a device first!")
    return
  
  # Check if this is a rename operation
  if loaded_profiles.has(profile_line_edit.text):
    # User may have edited an existing profile name - this is the rename
    pass
  
  save_profile(profile_name)
  
  # Reload profile list to show new/renamed profile
  load_profiles_list()
  
  print("Profile '", profile_name, "' saved successfully!")


func _on_back_button_pressed() -> void:
  # Change this path to your main menu scene
  get_tree().change_scene_to_file("res://main_menu.tscn")

func load_profiles_list() -> void:
  profile_popup_menu.clear()
  loaded_profiles.clear()
  
  # Load current active profile
  if FileAccess.file_exists(SETTINGS_FILE_PATH):
    var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
    current_active_profile = file.get_as_text().strip_edges()
    file.close()
  
  # Load all saved profiles
  var dir = DirAccess.open("user://")
  if not dir.dir_exists("controller_profiles"):
    dir.make_dir("controller_profiles")
    return
  
  var profile_dir = DirAccess.open("user://controller_profiles")
  if profile_dir:
    profile_dir.list_dir_begin()
    var file_name = profile_dir.get_next()
    
    while file_name != "":
      if not profile_dir.current_is_dir() and file_name.ends_with(".json"):
        var profile_name = file_name.trim_suffix(".json")
        loaded_profiles.append(profile_name)
        
        # Add circle indicator if this is the active profile
        var display_text = profile_name
        if profile_name == current_active_profile:
          display_text = "(active) " + profile_name
        
        profile_popup_menu.add_item(display_text, loaded_profiles.size() - 1)
      file_name = profile_dir.get_next()
    
    profile_dir.list_dir_end()
  
  if loaded_profiles.is_empty():
    profile_popup_menu.add_item("(No saved profiles)", -1)
    profile_popup_menu.set_item_disabled(0, true)
  
  print("Loaded ", loaded_profiles.size(), " profiles")



func load_profile(profile_name: String) -> void:
  var file_path = "user://controller_profiles/" + profile_name + ".json"
  
  if not FileAccess.file_exists(file_path):
    push_warning("Profile not found: ", profile_name)
    return
  
  var file = FileAccess.open(file_path, FileAccess.READ)
  var json_string = file.get_as_text()
  file.close()
  
  var json = JSON.new()
  var parse_result = json.parse(json_string)
  
  if parse_result != OK:
    push_warning("Error parsing profile JSON")
    return
  
  var profile_data = json.data
  
  # Restore device selection
  selected_device_id = profile_data.get("device_id", -1)
  selected_device_type = profile_data.get("device_type", "")
  
  # Find and select device in dropdown
  for i in range(device_dropdown.item_count):
    if device_dropdown.get_item_id(i) == selected_device_id:
      var metadata = device_dropdown.get_item_metadata(i)
      if metadata == selected_device_type:
        device_dropdown.select(i)
        break
  
  # Restore mappings
  column_mappings = profile_data.get("mappings", [])
  
  # Ensure we have 10 columns
  while column_mappings.size() < 10:
    column_mappings.append([])
  
  # Update all column displays
  for i in range(10):
    update_column_display(i)
  
  print("Loaded profile: ", profile_name)

func load_active_profile() -> void:
  if not FileAccess.file_exists(SETTINGS_FILE_PATH):
    return
  
  var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
  var active_profile_name = file.get_as_text().strip_edges()
  file.close()
  
  if active_profile_name.is_empty():
    return
  
  profile_line_edit.text = active_profile_name
  load_profile(active_profile_name)
  print("Loaded active profile: ", active_profile_name)


func set_active_profile(profile_name: String) -> void:
  var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
  file.store_string(profile_name)
  file.close()
  print("Set active profile: ", profile_name)

func _on_profile_selected(index: int) -> void:
  var item_id = device_dropdown.get_item_id(index)
  
  if item_id == -1:
    # "New Profile" selected - clear everything
    selected_device_id = -1
    selected_device_type = ""
    for i in range(10):
      column_mappings[i].clear()
      update_column_display(i)
    device_dropdown.select(0)
  else:
    # Load existing profile
    var profile_name = loaded_profiles[item_id]
    load_profile(profile_name)

func _on_set_active_pressed() -> void:
  var profile_name = profile_line_edit.text.strip_edges()
  
  if profile_name.is_empty():
    push_warning("Please enter or select a profile name!")
    return
  
  if not loaded_profiles.has(profile_name):
    push_warning("Profile must be saved before setting as active!")
    return
  
  set_active_profile(profile_name)
  current_active_profile = profile_name
  
  # Refresh the dropdown to show the circle indicator
  load_profiles_list()
  
  print("Set ", profile_name, " as active profile")


  
func _on_profile_dropdown_pressed() -> void:
  # Position popup below the line edit
  var popup_pos = profile_line_edit.global_position
  popup_pos.y += profile_line_edit.size.y
  profile_popup_menu.position = popup_pos
  profile_popup_menu.size.x = profile_line_edit.size.x + profile_dropdown_button.size.x
  profile_popup_menu.popup()

func _on_profile_popup_selected(id: int) -> void:
  if id == -1:
    return
  
  var profile_name = loaded_profiles[id]
  profile_line_edit.text = profile_name
  load_profile(profile_name)

func _on_profile_text_changed(new_text: String) -> void:
  # Optional: Filter popup menu items as user types
  pass
