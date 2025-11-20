extends Node2D

const COLUMN_COUNT = 10
const COLUMN_WIDTH = 100.0
const HIT_ZONE_Y = 500
const HIT_ZONE_HEIGHT = 10
const NOTE_SPEED = 300

@onready var column_dividers = $GameArea/ColumnDividers
@onready var notes_container = $Notes
@onready var music_player = $MusicPlayer
@onready var score_label = $UI/ScoreLabel
@onready var time_label = $UI/Label
@onready var sounds = $Sounds

# HitZone
@onready var hit_zone = $GameArea/HitZone
@onready var hit_zone_visual = $GameArea/HitZone/HitZoneVisual
@onready var hit_zone_collision = $GameArea/HitZone/HitZoneCollision

const Note = preload("res://components/note.tscn")

# Support Scripts
var chart_parser: ChartParser
var profile_loader: ProfileLoader = ProfileLoader.new()

# Screen
var screen_size: Vector2
var screen_width = 1000
var note_spawn_distance = 600
var travel_time = 0

# Song info
var dtx_dir: String = ""
var metadata: Dictionary = {}
var wav_sounds: Dictionary = {}
var bpm: float = 120.0

# Notes info
var notes_data: Array = []
var pending_non_column_notes: Array = []
var current_note_index: int = 0
var active_notes: Dictionary = {}

# Game info
var is_playing: bool = false
var time_elapsed: float = 0.0
var key_bindings: Dictionary = {}
var active_controller: String = ""
var score: int = 0

# Column note colors
var channel_colors = {
  0: Color(0.6, 0.7, 1.0), # Left Crash - Medium Blue
  1: Color(0.3, 0.8, 0.8), # HI-Hat - Cyan
  2: Color(0.9, 0.7, 0.6), # Left Pedal
  3: Color(1.0, 0.3, 0.3), # Snare - Red
  4: Color(1.0, 0.8, 0.2), # High Tom - Yellow
  5: Color(0.8, 0.2, 0.8), # Bass - Purple
  6: Color(1.0, 0.6, 0.2), # Low Tom - Orange
  7: Color(0.3, 1.0, 0.3), # Floor Tom - Green
  8: Color(0.9, 0.5, 0.1), # Crash - Dark Orange
  9: Color(0.7, 0.9, 1.0), # Ride - Very Light Blue
}


func _ready():
  screen_size = get_viewport_rect().size
  screen_width = screen_size.x
  note_spawn_distance = screen_size.y
  travel_time = note_spawn_distance / NOTE_SPEED
  
  score = 0
  dtx_dir = GlobalSongData.selected_song_path.get_base_dir()

  _update_score_display()
  _setup_hit_zone()
  _setup_columns()

  key_bindings = profile_loader.load_key_bindings()

  _set_active_controller()
  _load_selected_song()
  _setup_sounds()
  is_playing = true


func _update_score_display():
  score_label.text = "Score: " + str(score)


func _setup_columns():
  for i in range(COLUMN_COUNT + 1):
    var line = Line2D.new()
    line.add_point(Vector2(i * COLUMN_WIDTH, 0))
    line.add_point(Vector2(i * COLUMN_WIDTH, 600))
    line.default_color = Color(0.3, 0.3, 0.3, 0.5)
    line.width = 2
    column_dividers.add_child(line)


func _setup_hit_zone():
  hit_zone_visual.size = Vector2(screen_width, HIT_ZONE_HEIGHT)
  hit_zone_visual.position = Vector2(0, HIT_ZONE_Y)
  hit_zone_visual.color = Color.WHITE
  
  var rect_shape = RectangleShape2D.new()
  rect_shape.size = Vector2(screen_width, HIT_ZONE_HEIGHT * 2)
  hit_zone_collision.shape = rect_shape
  hit_zone_collision.position = Vector2(screen_width / 2, HIT_ZONE_Y)


func _set_active_controller():
  active_controller = key_bindings["device_type"]
  
  if active_controller == "midi":
    OS.open_midi_inputs()
  

func _load_selected_song():
  if GlobalSongData.selected_song_metadata == null:
    print("No song selected!")
    return

  var song = GlobalSongData.selected_song_metadata
  print("Playing: ", song.title, " by ", song.artist)
  
  # Initialize chart parser
  chart_parser = ChartParser.new()
  
  # Parse the chart file
  if not chart_parser.parse_chart_file(GlobalSongData.selected_song_path):
    print("Failed to parse chart file!")
    return
  
  # Get metadata
  metadata = chart_parser.get_metadata()
  wav_sounds = chart_parser.get_wav_sounds()

  if metadata.has("bpm"):
    bpm = float(metadata.get("bpm"))
  elif song.bpm != null:
    bpm = float(song.bpm)
  else:
    bpm = 120.0
  
  print("BPM: ", bpm)
  
  # Process notes from parser
  _process_parsed_notes()
  print("Loaded ", notes_data.size(), " notes")
  

func _process_parsed_notes():
  notes_data.clear()
  var parsed_notes = chart_parser.get_sorted_notes()
  
  # Group notes by time for simultaneous spawning
  var temp_notes = {}
  
  for note in parsed_notes:
    # Convert bar time to seconds using the correct BPM
    var note_time = chart_parser.bar_to_seconds(note.time, bpm)
    var color = channel_colors.get(note.column, Color.WHITE)
    
    # Group by time
    if not temp_notes.has(note_time):
      temp_notes[note_time] = []
    
    temp_notes[note_time].append({
      "time": note_time + travel_time,
      "column": note.column,
      "color": color,
      "channel": note.channel,
      "sound_code": note.sound_code
    })
  
  # Convert to sorted array
  var note_times = temp_notes.keys()
  note_times.sort()
  
  for note_time in note_times:
    for note_info in temp_notes[note_time]:
      notes_data.append(note_info)


func _setup_sounds():
  for key in wav_sounds.keys():
    var audio_player = AudioStreamPlayer.new()
    audio_player.name = key
    audio_player.set_volume_linear(wav_sounds[key].volume / 100)

    var path = _get_audio_file_path(key)
    _load_audio(audio_player, path)

    sounds.add_child(audio_player)


func _process(_delta):
  var playback_pos = 0

  if music_player.playing:
    playback_pos = music_player.get_playback_position()

  while current_note_index < notes_data.size():
    var note_info = notes_data[current_note_index]
    var spawn_time = note_info.time - travel_time
    
    if (playback_pos and playback_pos >= spawn_time) or time_elapsed >= spawn_time:
      _execute_note(note_info)
      current_note_index += 1
    else:
      break

  var i = 0
  while i < pending_non_column_notes.size():
    var note_info = pending_non_column_notes[i]
    if (playback_pos and playback_pos >= note_info.time) or time_elapsed >= note_info.time:
      _execute_non_column_note(note_info)
      pending_non_column_notes.remove_at(i)
    else:
      i += 1


func _physics_process(delta):
  if not is_playing or notes_data.is_empty():
    return
  
  time_elapsed += delta


func _get_audio_time() -> float:
  if not music_player.playing:
    return 0.0
  
  var time = music_player.get_playback_position() + AudioServer.get_time_since_last_mix()
  time -= AudioServer.get_output_latency()
  return time


func _execute_note(note_info) -> void:
  if note_info.column != null:
    _spawn_note_from_data(note_info, note_info.time)
  else:
    pending_non_column_notes.append(note_info)


func _execute_non_column_note(note_info) -> void:
  if note_info.channel == "0x01":
    _load_bgm(note_info.sound_code)
  elif note_info.channel == "0x08":
    _change_bpm(note_info.sound_code)


func _spawn_note_from_data(note_info: Dictionary, hit_time: float):
  var note = Note.instantiate()
  var spawn_y = HIT_ZONE_Y - note_spawn_distance
  note.position = Vector2(get_column_x_position(note_info.column), spawn_y)
  note.set_note_color(note_info.color)
  note.set_column(note_info.column)
  
  # Store the exact time this note should reach the hit zone
  note.set_meta("hit_time", hit_time)
  note.set_meta("spawn_time", _get_audio_time())
  note.set_meta("column", note_info.column)
  note.set_meta("sound_code", note_info.sound_code)
  
  notes_container.add_child(note)


func get_column_x_position(column_index: int) -> float:
  return float(column_index) * COLUMN_WIDTH + COLUMN_WIDTH / 2


func _load_bgm(sound_code: String) -> void:
  var bgm_file = _get_audio_file_path(sound_code)
  if not bgm_file.is_empty():
    _load_audio(music_player, bgm_file)
    
  if music_player.stream != null:
    music_player.play()


func _get_audio_file_path(file_key: String) -> String:
  if wav_sounds.has(file_key):
    return dtx_dir + "/" + wav_sounds[file_key].file_path
  
  return ""


func _load_audio(audio_stream_player: AudioStreamPlayer, audio_path: String):
  print("Loading audio: ", audio_path)
  
  if not FileAccess.file_exists(audio_path):
    print("Audio file not found: ", audio_path)
    return
  
  var extension = audio_path.get_extension().to_lower()
  
  if extension == "ogg":
    var audio_stream = AudioStreamOggVorbis.load_from_file(audio_path)
    if audio_stream:
      audio_stream_player.stream = audio_stream
      print("Loaded OGG file")
  else:
    print("File type not supported")


func _change_bpm(sound_code: String) -> void:
  bpm = float(metadata["bpm" + sound_code.to_lower()])


func _input(event):
  if not is_playing:
    return
  
  for column in range(COLUMN_COUNT):
    if _is_column_key_pressed(column, event):
      _handle_column_hit(column)
      

func _is_column_key_pressed(column: int, event: InputEvent) -> bool:
  if not key_bindings.has("mappings") or column >= key_bindings["mappings"].size():
    return false
  
  var column_mapping = key_bindings["mappings"][column]
  
  if column_mapping.size() == 0:
    return false
  
  for key in column_mapping:
    var input_type = key.get("type", "")
    
    if input_type == "keyboard":
      if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == key.get("keycode", -1):
          return true
    
    elif input_type == "midi_note":
      if event is InputEventMIDI:
        # Check for NOTE_ON message with velocity > 0
        if event.message == MIDI_MESSAGE_NOTE_ON and event.velocity > 0:
          # Match MIDI note/pitch
          var expected_note = int(key.get("note", -1))
          if event.pitch == expected_note:
            # Match MIDI channel (convert to 0-indexed)
            var expected_channel = int(key.get("channel", 0))
            if event.channel == expected_channel:
              return true
    
    elif input_type == "midi_cc":
      if event is InputEventMIDI:
        # Check for CONTROL_CHANGE message
        if event.message == MIDI_MESSAGE_CONTROL_CHANGE:
          # Match controller number
          var expected_controller = int(key.get("controller", -1))
          if event.controller_number == expected_controller:
            # Match MIDI channel
            var expected_channel = int(key.get("channel", 0))
            if event.channel == expected_channel:
              # Check if controller value is above threshold (e.g., pressed)
              if event.controller_value > 64:
                return true
    
    elif input_type == "controller" or input_type == "joypad":
      if event is InputEventJoypadButton and event.pressed:
        # Match button index
        if event.button_index == key.get("button_index", -1):
          # Optionally check device_id if specified
          if key.has("device_id"):
            if event.device == key.get("device_id"):
              return true
          else:
            return true
  
  return false


func _handle_column_hit(column: int):
  if not active_notes.has(column):
    print("Miss - No note in column ", column)
    return
  
  var note = active_notes[column]
  var hit_time = note.get_meta("hit_time")
  var current_time = _get_audio_time()
  var timing_difference = abs(current_time - hit_time)
  var sound_player = sounds.get_node(note.get_meta("sound_code"))
  sound_player.play()
  
  # Calculate score based on accuracy
  var points = _calculate_score(timing_difference)
  score += points
  _update_score_display()
  
  # Remove the note
  active_notes.erase(column)
  note.queue_free()
  
  print("Hit! Column: ", column, " Accuracy: ", timing_difference, " Points: ", points)


func _calculate_score(timing_difference: float) -> int:
  # Perfect hit zone (within 50ms of white line)
  if timing_difference <= 0.05:
    return 100
  # Great hit zone (within 100ms)
  elif timing_difference <= 0.10:
    return 50
  # Good hit zone (within 150ms)
  elif timing_difference <= 0.15:
    return 25
  # Okay hit zone (within 200ms)
  elif timing_difference <= 0.20:
    return 10
  else:
    return 0


func _on_hit_zone_area_entered(area: Area2D):
  if area.is_in_group("notes"):
    var column = area.get_meta("column") if area.has_meta("column") else -1
    if column >= 0:
      active_notes[column] = area
    #print("Note entered hit zone: ", area.name)

func _on_hit_zone_area_exited(area: Area2D):
  if area.is_in_group("notes"):
    var column = area.get_meta("column") if area.has_meta("column") else -1
    if column >= 0 and active_notes.has(column):
      active_notes.erase(column)
    #print("Note exited hit zone: ", area.name)


func _on_music_player_finished():
  SceneManager.goto_scene("song_select")
