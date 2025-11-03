extends Control

const SONGS_FOLDER = "res://songs/"

@onready var song_list = $MarginContainer/VBoxContainer/SongList
@onready var song_info = $MarginContainer/VBoxContainer/InfoPanel/MarginContainer/SongInfo
@onready var title_label = $MarginContainer/VBoxContainer/Title

var song_data: Array = []

class SongMetadata:
  var file_path: String
  var title: String = "Unknown"
  var artist: String = "Unknown"
  var genre: String = ""
  var bpm: String = "0"
  var dlevel: String = "0"
  var preview: String = ""
  var preimage: String = ""
  
  func get_display_name() -> String:
    return "%s - %s" % [title, artist]

func _ready():
  _setup_ui()
  _load_songs()
  _populate_song_list()
  
  if song_data.size() > 0:
    song_list.select(0)
    _update_info_display(0)

func _setup_ui():
  # Setup background
  var bg = $Background
  bg.color = Color(0.1, 0.1, 0.15)
  bg.set_anchors_preset(Control.PRESET_FULL_RECT)
  
  # Setup title
  title_label.text = "SELECT SONG"
  title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  title_label.add_theme_font_size_override("font_size", 32)
  
  # Setup song list
  song_list.custom_minimum_size = Vector2(800, 400)
  song_list.add_theme_font_size_override("font_size", 20)
  
  # Connect signals
  song_list.item_selected.connect(_on_song_selected)
  song_list.item_activated.connect(_on_song_activated)

func _load_songs():
  # Check if songs folder exists
  if not DirAccess.dir_exists_absolute(SONGS_FOLDER):
    print("Songs folder not found: ", SONGS_FOLDER)
    return
  
  # Get all files in songs folder and subfolders
  _scan_directory(SONGS_FOLDER)
  
  print("Found %d DTX files" % song_data.size())

func _scan_directory(path: String):
  var dir = DirAccess.open(path)
  if dir == null:
    print("Error opening directory: ", path)
    return
  
  dir.list_dir_begin()
  var file_name = dir.get_next()
  
  while file_name != "":
    var full_path = path + "/" + file_name
    
    if dir.current_is_dir():
      # Skip . and .. directories
      if file_name != "." and file_name != "..":
        _scan_directory(full_path)
    else:
      # Check if it's a DTX file
      if file_name.get_extension().to_lower() == "dtx":
        var metadata = _parse_dtx_file(full_path)
        if metadata:
          song_data.append(metadata)
    
    file_name = dir.get_next()
  
  dir.list_dir_end()

func _parse_dtx_file(file_path: String) -> SongMetadata:
  var file = FileAccess.open(file_path, FileAccess.READ)
  if file == null:
    print("Error opening file: ", file_path)
    return null

  var metadata = SongMetadata.new()
  metadata.file_path = file_path

  # Read line by line with error handling
  while not file.eof_reached():
    var line = _read_line_safe(file)
    if line == null:
      continue

    line = line.strip_edges()

    # Stop reading when we hit the note data section
    if line.begins_with("#0") and line.length() > 6:
      break

    # Parse metadata fields - use contains() instead of begins_with for safety
    if "#TITLE:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.title = parts[1].strip_edges()
    elif "#ARTIST:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.artist = parts[1].strip_edges()
    elif "#GENRE:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.genre = parts[1].strip_edges()
    elif "#BPM:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.bpm = parts[1].strip_edges()
    elif "#DLEVEL:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.dlevel = parts[1].strip_edges()
    elif "#PREVIEW:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.preview = parts[1].strip_edges()
    elif "#PREIMAGE:" in line:
      var parts = line.split(":", true, 1)
      if parts.size() > 1:
        metadata.preimage = parts[1].strip_edges()

  file.close()
  return metadata
  
func _read_line_safe(file: FileAccess) -> String:
  # Read line byte by byte to handle encoding issues
  var line_bytes = PackedByteArray()

  while not file.eof_reached():
    var byte = file.get_8()

    # Line break detection
    if byte == 10:  # \n
      break
    elif byte == 13:  # \r
      # Check for \r\n
      if not file.eof_reached():
        var next_byte = file.get_8()
        if next_byte != 10:
          file.seek(file.get_position() - 1)
        break

    line_bytes.append(byte)

  # Convert to string safely
  return _buffer_to_string_safe(line_bytes)


func _buffer_to_string_safe(buffer: PackedByteArray) -> String:
  var result = ""

  # Try to decode as UTF-8 first, character by character
  for i in range(buffer.size()):
    var byte = buffer[i]

    # ASCII range (0-127) is safe in both UTF-8 and Latin-1
    if byte < 128:
      result += char(byte)
    else:
      # For non-ASCII, try to handle as Latin-1 or skip
      # This handles common Windows-1252 characters
      if byte >= 160:  # Printable Latin-1 range
        result += char(byte)
      else:
        # Skip or replace control characters
        result += " "

  return result


func _populate_song_list():
  song_list.clear()
  
  if song_data.is_empty():
    song_list.add_item("No songs found in 'songs' folder")
    song_list.set_item_disabled(0, true)
    return
  
  # Sort by title
  song_data.sort_custom(func(a, b): return a.title < b.title)
  
  # Add songs to list
  for song in song_data:
    song_list.add_item(song.get_display_name())

func _on_song_selected(index: int):
  _update_info_display(index)

func _on_song_activated(index: int):
  _load_song(index)

func _update_info_display(index: int):
  if index < 0 or index >= song_data.size():
    return
  
  var song = song_data[index]
  var info_text = ""
  info_text += "Title: %s\n" % song.title
  info_text += "Artist: %s\n" % song.artist
  if song.genre != "":
    info_text += "Genre: %s\n" % song.genre
  info_text += "BPM: %s\n" % song.bpm
  info_text += "Difficulty: %s\n" % song.dlevel
  info_text += "\nPress ENTER or Double-Click to play"
  
  song_info.text = info_text

func _load_song(index: int):
  if index < 0 or index >= song_data.size():
    return
  
  var song = song_data[index]
  print("Loading song: ", song.title)
  
  # Store selected song data globally so rhythm_game can access it
  # You can use an autoload singleton for this
  GlobalSongData.selected_song_path = song.file_path
  GlobalSongData.selected_song_metadata = song
  
  # Change to rhythm game scene
  get_tree().change_scene_to_file("res://rhythm_game.tscn")

func _input(event):
  # Alternative: Press ENTER to select current item
  if event.is_action_pressed("ui_accept"):
    var selected = song_list.get_selected_items()
    if selected.size() > 0:
      _load_song(selected[0])
