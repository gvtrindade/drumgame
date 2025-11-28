extends Node2D

const COLUMN_COUNT = 10
const COLUMN_WIDTH = 80.0
const MARGIN_SIDE = 100.0
const HIT_ZONE_Y = 500
const HIT_ZONE_HEIGHT = 10
const NOTE_SPEED = 300
const BEATS_PER_BAR = 4.0
const TICKS_PER_BAR = 96.0

@onready var column_dividers = $GameArea/ColumnDividers
@onready var notes_container = $Notes
@onready var music_player = $MusicPlayer
@onready var score_label = $UI/ScoreLabel
@onready var bar_track_label = $UI/BarTrackerLabel
@onready var sounds = $Sounds

# HitZone
@onready var hit_zone = $GameArea/HitZone
@onready var hit_zone_visual = $GameArea/HitZone/HitZoneVisual
@onready var hit_zone_window = $GameArea/HitZone/HitZoneWindow
@onready var grid_lines_container = $GridLines

const Note = preload("res://components/note.tscn")
const TickLine = preload("res://components/tick_line.tscn")


# Support Scripts
var chart_parser: ChartParser
var notification_manager: TextNotificationManager
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
var miliseconds_per_beat: float = (60.0 / bpm) * 1000.0
var miliseconds_per_bar: float = 0.0
var is_tracking_time: bool = false
var current_tick: int = 0
var chart_time: float = 0.0
var spawned_tick_lines: Dictionary = {}

# Notes info
var notes_data: Array = []
var pending_non_column_notes: Array = []
var current_note_index: int = 0
var active_notes: Dictionary = {
  0: [],
  1: [],
  2: [],
  3: [],
  4: [],
  5: [],
  6: [],
  7: [],
  8: [],
  9: [],
}

# Game info
var is_playing: bool = false
var time_elapsed: float = 0.0
var key_bindings: Dictionary = {}
var active_controller: String = ""
var score: int = 0
var debug: bool = true


func _ready():
  screen_size = get_viewport_rect().size
  screen_width = screen_size.x
  note_spawn_distance = screen_size.y
  travel_time = (note_spawn_distance / NOTE_SPEED) * 1000.0

  notification_manager = TextNotificationManager.new()
  add_child(notification_manager)
  
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
  is_tracking_time = true
  chart_time = - travel_time

func _update_score_display():
  score_label.text = "Score: " + str(score)


func _setup_columns():
  for i in range(COLUMN_COUNT + 1):
    var line = Line2D.new()
    var x_pos = MARGIN_SIDE + (i * COLUMN_WIDTH)
    line.add_point(Vector2(x_pos, 0))
    line.add_point(Vector2(x_pos, 600))
    line.default_color = Color(0.5, 0.5, 0.5, 1.0)
    line.width = 2
    column_dividers.add_child(line)


func _setup_hit_zone():
  var game_area_width = COLUMN_COUNT * COLUMN_WIDTH
  hit_zone_visual.size = Vector2(game_area_width, HIT_ZONE_HEIGHT)
  hit_zone_visual.position = Vector2(MARGIN_SIDE, HIT_ZONE_Y)
  hit_zone_visual.color = Color.WHITE
  
  var rect_shape = RectangleShape2D.new()
  rect_shape.size = Vector2(game_area_width, HIT_ZONE_HEIGHT * 2)
  hit_zone_window.shape = rect_shape
  hit_zone_window.position = Vector2(screen_width / 2, HIT_ZONE_Y)

  var center_line = ColorRect.new()
  center_line.name = "CenterLineVisual"
  center_line.color = Color(0.2, 0.2, 0.2, 1.0) # Dark gray line
  center_line.size = Vector2(game_area_width, 2) # 2px thick
  center_line.position = Vector2(0, HIT_ZONE_HEIGHT / 2.0 - 1.0) # Centered inside visual
  hit_zone_visual.add_child(center_line)

  var trigger_area = Area2D.new()
  trigger_area.name = "CenterLineTrigger"
  trigger_area.add_to_group("auto_hit")
  hit_zone.add_child(trigger_area)

  var trigger_shape = CollisionShape2D.new()
  var shape = RectangleShape2D.new()
  shape.size = Vector2(screen_width, 2) # Thin trigger line
  trigger_shape.shape = shape

  # Position strictly in the middle of the visual
  # Visual starts at HIT_ZONE_Y. Middle is + Height/2
  trigger_shape.position = Vector2(screen_width / 2.0, HIT_ZONE_Y + HIT_ZONE_HEIGHT / 2.0)
  trigger_area.add_child(trigger_shape)


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
    
  miliseconds_per_beat = (60.0 / bpm) * 1000.0
  miliseconds_per_bar = miliseconds_per_beat * BEATS_PER_BAR
  
  print("BPM: ", bpm)
  
  # Process notes from parser
  notes_data = chart_parser.get_sorted_notes()
  print("Loaded ", notes_data.size(), " notes")


func _setup_sounds():
  for key in wav_sounds.keys():
    var audio_player = AudioStreamPlayer.new()
    audio_player.name = key
    
    audio_player.set_volume_linear(float(wav_sounds[key].volume) / 100.0)

    var path = _get_audio_file_path(key)
    _load_audio(audio_player, path)

    sounds.add_child(audio_player)


func _process(_delta):
  while current_note_index < notes_data.size():
    _spawn_tick_line()
    bar_track_label.text = "Time: %f" % chart_time
    
    var note_info = notes_data[current_note_index]
    var spawn_time = get_note_target_time(note_info)
    
    if time_elapsed >= spawn_time:
      _execute_note(note_info, spawn_time)
      current_note_index += 1
    else:
      break

  var i = 0
  while i < pending_non_column_notes.size():
    var note_info = pending_non_column_notes[i]
    var hit_time = get_note_target_time(note_info) + travel_time

    if time_elapsed >= hit_time:
      _execute_non_column_note(note_info)
      pending_non_column_notes.remove_at(i)
    else:
      i += 1


func get_note_target_time(note) -> float:
  var total_bars: float = note.bar + (note.position / TICKS_PER_BAR)
  return total_bars * miliseconds_per_bar


func _execute_note(note_info, hit_time) -> void:
  if note_info.column != null:
    _spawn_note_from_data(note_info, hit_time)
  else:
    pending_non_column_notes.append(note_info)


func _physics_process(delta):
  if not is_playing or notes_data.is_empty():
    return

  time_elapsed += delta * 1000.0

  if is_tracking_time:
    chart_time += delta * 1000.0


func _execute_non_column_note(note_info) -> void:
  if note_info.channel == "0x01":
    _load_bgm(note_info.sound_code)
  elif note_info.channel == "0x08":
    _change_bpm(note_info.sound_code)


func _change_bpm(sound_code: String) -> void:
  bpm = float(metadata["bpm" + sound_code.to_lower()])
  miliseconds_per_beat = (60.0 / bpm) * 1000
  miliseconds_per_bar = miliseconds_per_beat * BEATS_PER_BAR
  notification_manager.spawn_text("Changed bpm to %f" % bpm)


func _spawn_note_from_data(note_info: Dictionary, hit_time: float):
  var note = Note.instantiate()
  var spawn_y = HIT_ZONE_Y - note_spawn_distance
  note.position = Vector2(get_column_x_position(note_info.column), spawn_y)
  note.set_note_color(note_info.color)
  note.set_column(note_info.column)
  
  # Store the exact time this note should reach the hit zone
  note.set_meta("hit_time", hit_time)
  note.set_meta("spawn_time", time_elapsed)
  note.set_meta("column", note_info.column)
  note.set_meta("sound_code", note_info.sound_code)
  
  note.add_to_group("notes")

  note.connect("area_entered", _on_center_line_trigger_entered.bind(note_info.column))
  notes_container.add_child(note)


func get_column_x_position(column_index: int) -> float:
  return MARGIN_SIDE + float(column_index) * COLUMN_WIDTH + COLUMN_WIDTH / 2


func _on_center_line_trigger_entered(area: Area2D, column: int):
  if area.is_in_group("auto_hit") and debug:
      _handle_column_hit(column)

func _get_audio_time() -> float:
  if not music_player.playing:
    return 0.0
  
  var time = music_player.get_playback_position() + AudioServer.get_time_since_last_mix()
  time -= AudioServer.get_output_latency()
  return time


func _load_bgm(sound_code: String) -> void:
  var bgm_file = _get_audio_file_path(sound_code)
  if not bgm_file.is_empty():
    _load_audio(music_player, bgm_file)
    
  if music_player.stream != null:
    music_player.play()
    notification_manager.spawn_text("Loaded song")


func _get_audio_file_path(file_key: String) -> String:
  if wav_sounds.has(file_key):
    var path: String = wav_sounds[file_key].file_path
    if path.begins_with(".."):
      var last_bar = dtx_dir.rfind("/")
      var new_dtx_dir = dtx_dir.substr(0, last_bar)
      var address_index = path.find("\\")
      return new_dtx_dir + path.substr(address_index)

    return dtx_dir + "/" + path
  return ""


func _load_audio(audio_stream_player: AudioStreamPlayer, audio_path: String):
  if not FileAccess.file_exists(audio_path):
    print("Audio file not found: ", audio_path)
    return
  
  var extension = audio_path.get_extension().to_lower()
  
  if extension == "ogg":
    var audio_stream = AudioStreamOggVorbis.load_from_file(audio_path)
    if audio_stream:
      audio_stream_player.stream = audio_stream
  elif extension == "wav":
    var audio_stream = AudioStreamWAV.load_from_file(audio_path)
    if audio_stream:
      audio_stream_player.stream = audio_stream
  else:
    print("Could not load file: %s" % audio_path)


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
  if active_notes[column].is_empty():
    print("Miss - No note in column ", column)
    return
  
  var note = active_notes[column][0]
  var hit_time = note.get_meta("hit_time")
  var timing_difference = abs(chart_time - hit_time)
  print("Hit: %s, ex: %s" % [chart_time, hit_time])
  var sound_player = sounds.get_node(note.get_meta("sound_code"))
  sound_player.play()
  
  # Calculate score based on accuracy
  # if not debug:
  var points = _calculate_score(timing_difference)
  score += points
  _update_score_display()
  # print("Hit! Column: ", column, " Accuracy: ", timing_difference, " Points: ", points)
  
  active_notes[column].erase(note)
  note.queue_free()


func _calculate_score(timing_difference: float) -> int:
  # Perfect hit zone (within 50ms of white line)
  if timing_difference <= 0.05:
    return 100
  # Great hit zone (within 100ms)
  if timing_difference <= 0.10:
    return 50
  # Good hit zone (within 150ms)
  if timing_difference <= 0.15:
    return 25
  # Okay hit zone (within 200ms)
  if timing_difference <= 0.20:
    return 10
    
  return 0


func _on_hit_zone_area_entered(area: Area2D):
  if area.is_in_group("notes"):
    var column = area.get_meta("column") if area.has_meta("column") else -1
    if column >= 0:
      # Add the new note to the end of the list
      active_notes[column].append(area)


func _on_hit_zone_area_exited(area: Area2D):
  if area.is_in_group("notes"):
    var column = area.get_meta("column") if area.has_meta("column") else -1
    if column >= 0 and active_notes.has(column):
      # Remove this specific note instance from the array
      active_notes[column].erase(area)


func _on_music_player_finished():
  SceneManager.goto_scene("song_select")


func _on_volume_slider_value_changed(value):
  music_player.volume_db = linear_to_db(value)


func _on_debug_toggle_pressed():
  debug = !debug
  var status = "enabled" if debug else "disabled"
  notification_manager.spawn_text("Debug mode " + status)


func _spawn_tick_line() -> void:
  # Only spawn on specific beats within the 96-tick measure
  var next_beat = int((chart_time + travel_time) / miliseconds_per_beat)
  var correspondent_beat = next_beat % 4
  if correspondent_beat not in [0, 1, 2, 3]:
    return
  
  # Only spawn if we haven't already spawned for this tick
  if spawned_tick_lines.has(next_beat):
    return
  
  # Create the tick line
  var tick_line = TickLine.instantiate()
  grid_lines_container.add_child(tick_line)
  
  # Determine if this is a major beat (on beat 0 of the measure)
  var is_major_beat = correspondent_beat == 0
  
  # Calculate spawn position
  var spawn_y = HIT_ZONE_Y - note_spawn_distance
  
  # Setup the line with all parameters
  tick_line.setup(
    next_beat,
    MARGIN_SIDE,
    COLUMN_COUNT,
    COLUMN_WIDTH,
    spawn_y,
    is_major_beat
  )
  
  spawned_tick_lines[next_beat] = tick_line
