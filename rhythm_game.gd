extends Node2D

const COLUMN_COUNT = 10
const COLUMN_WIDTH = 100
const HIT_ZONE_Y = 500
const HIT_ZONE_HEIGHT = 10
const NOTE_SPEED = 300

@onready var column_dividers = $GameArea/ColumnDividers
@onready var hit_zone = $GameArea/HitZone
@onready var notes_container = $Notes
@onready var music_player = $MusicPlayer

const Note = preload("res://note.tscn")

# Chart parser instance
var chart_parser: ChartParser

# Song data
var SCREEN_WIDTH = 1000
var SPAWN_DISTANCE = 600
var screen_size: Vector2
var bpm: float = 120.0
var beats_per_second: float = 2.0
var seconds_per_beat: float = 0.5
var song_start_time: float = 0.0
var time_begin: int = 0
var notes_data: Array = []
var current_note_index: int = 0
var is_playing: bool = false

# Channel to color mapping
var channel_colors = {
  0: Color(0.6, 0.7, 1.0),    # Left Crash - Medium Blue
  1: Color(0.3, 0.8, 0.8),    # HI-Hat - Cyan
  2: Color(0.9, 0.7, 0.6),    # Left Pedal
  3: Color(1.0, 0.3, 0.3),    # Snare - Red
  4: Color(1.0, 0.8, 0.2),    # High Tom - Yellow
  5: Color(0.8, 0.2, 0.8),    # Bass - Purple
  6: Color(1.0, 0.6, 0.2),    # Low Tom - Orange
  7: Color(0.3, 1.0, 0.3),    # Floor Tom - Green
  8: Color(0.9, 0.5, 0.1),    # Crash - Dark Orange
  9: Color(0.7, 0.9, 1.0),    # Ride - Very Light Blue
}


func _ready():
  screen_size = get_viewport_rect().size
  SCREEN_WIDTH = screen_size.x
  SPAWN_DISTANCE = screen_size.y
  _setup_columns()
  _setup_hit_zone()
  _load_selected_song()


func _process(delta):
  if not is_playing or notes_data.is_empty():
    return
  
  # Get accurate audio time
  var current_time = _get_audio_time()
  
  # Calculate how long it takes for a note to travel from spawn to hit zone
  var travel_time = SPAWN_DISTANCE / NOTE_SPEED
  
  # Spawn notes that need to start traveling now
  while current_note_index < notes_data.size():
    var note_info = notes_data[current_note_index]
    # Spawn the note travel_time seconds before it should be hit
    var spawn_time = note_info.time - travel_time
    
    if current_time >= spawn_time:
      _execute_note(note_info)
      current_note_index += 1
    else:
      break


func _execute_note(note_info) -> void:
    if note_info.column != null: 
      _spawn_note_from_data(note_info, note_info.time)
      print("Note swpawned for time: " + str(note_info.time))
    elif note_info.channel == "0x01":
      _load_bgm()
    elif note_info.channel == "0x08":
      _change_bpm(note_info.sound_code)
  
  
func _spawn_note_from_data(note_info: Dictionary, hit_time: float):
  var note = Note.instantiate()
  var spawn_y = HIT_ZONE_Y - SPAWN_DISTANCE
  note.position = Vector2(get_column_x_position(note_info.column), spawn_y)
  note.set_note_color(note_info.color)
  note.set_column(note_info.column)
  
  # Store the exact time this note should reach the hit zone
  note.set_meta("hit_time", hit_time)
  note.set_meta("spawn_time", _get_audio_time())
  
  notes_container.add_child(note)


func _get_audio_time() -> float:
  if not music_player.playing:
    return 0.0
  
  var time = music_player.get_playback_position() + AudioServer.get_time_since_last_mix()
  time -= AudioServer.get_output_latency()
  return time


func _setup_columns():
  for i in range(COLUMN_COUNT + 1):
    var line = Line2D.new()
    line.add_point(Vector2(i * COLUMN_WIDTH, 0))
    line.add_point(Vector2(i * COLUMN_WIDTH, 600))
    line.default_color = Color(0.3, 0.3, 0.3, 0.5)
    line.width = 2
    column_dividers.add_child(line)

func _setup_hit_zone():
  var hit_visual = ColorRect.new()
  hit_visual.name = "HitZoneVisual"
  hit_visual.size = Vector2(SCREEN_WIDTH, HIT_ZONE_HEIGHT)
  hit_visual.position = Vector2(0, HIT_ZONE_Y)
  hit_visual.color = Color.WHITE
  hit_zone.add_child(hit_visual)
  
  var collision_shape = CollisionShape2D.new()
  collision_shape.name = "HitZoneCollision"
  var rect_shape = RectangleShape2D.new()
  rect_shape.size = Vector2(SCREEN_WIDTH, HIT_ZONE_HEIGHT * 2)
  collision_shape.shape = rect_shape
  collision_shape.position = Vector2(SCREEN_WIDTH / 2, HIT_ZONE_Y)
  hit_zone.add_child(collision_shape)
  
  hit_zone.area_entered.connect(_on_note_entered_hit_zone)
  hit_zone.area_exited.connect(_on_note_exited_hit_zone)

func _on_note_entered_hit_zone(area: Area2D):
  if area.is_in_group("notes"):
    print("Note entered hit zone: ", area.name)

func _on_note_exited_hit_zone(area: Area2D):
  if area.is_in_group("notes"):
    print("Note exited hit zone: ", area.name)

func get_column_x_position(column_index: int) -> float:
  return column_index * COLUMN_WIDTH + COLUMN_WIDTH / 2

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
  var metadata = chart_parser.get_metadata()
  #
  ## Set BPM
  if metadata.has("bpm"):
    bpm = float(metadata.bpm)
  elif song.has("bpm"):
    bpm = float(song.bpm)
  else:
    bpm = 120.0
  
  beats_per_second = bpm / 60.0
  seconds_per_beat = 60.0 / bpm
  
  print("BPM: ", bpm)
  
  # Process notes from parser
  _process_parsed_notes()
  print("Loaded ", notes_data.size(), " notes")
  
  await get_tree().create_timer(1.0).timeout    
  is_playing = true
  

func _load_bgm() -> void:
  var bgm_file = _get_bgm_file_path()
  if not bgm_file.is_empty():
    _load_audio(bgm_file)
    
  if music_player.stream != null:
    music_player.play()


func _change_bpm(sound_code: String) -> void:  
  var metadata = chart_parser.get_metadata()
  var bpm = float(metadata["bpm" + sound_code])
  beats_per_second = bpm / 60.0
  seconds_per_beat = 60.0 / bpm


func _get_bgm_file_path() -> String:
  var metadata = chart_parser.get_metadata()
  var wav_sounds = chart_parser.get_wav_sounds()
  var dtx_dir = GlobalSongData.selected_song_path.get_base_dir()
  
  # Check for BGMWAV reference
  if metadata.has("bgmwav"):
    var bgm_id = metadata.bgmwav
    if wav_sounds.has(bgm_id):
      return dtx_dir + "/" + wav_sounds[bgm_id].file_path
  
  # Check for WAV01 as common BGM convention
  if wav_sounds.has("01") and wav_sounds["01"].file_path.ends_with("ogg"):
    return dtx_dir + "/" + wav_sounds["01"].file_path
  
  return ""

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
      "time": note_time,
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


func _load_audio(audio_path: String):
  print("Loading audio: ", audio_path)
  
  if not FileAccess.file_exists(audio_path):
    print("Audio file not found: ", audio_path)
    return
  
  var extension = audio_path.get_extension().to_lower()
  
  if extension == "ogg":
    var audio_stream = AudioStreamOggVorbis.load_from_file(audio_path)
    if audio_stream:
      music_player.stream = audio_stream
      print("Loaded OGG file")
