extends Node2D

const COLUMN_COUNT = 10
const SCREEN_WIDTH = 1000
const COLUMN_WIDTH = SCREEN_WIDTH / COLUMN_COUNT
const HIT_ZONE_Y = 500
const HIT_ZONE_HEIGHT = 10
const NOTE_SPEED = 300
const SPAWN_DISTANCE = 600

@onready var column_dividers = $GameArea/ColumnDividers
@onready var hit_zone = $GameArea/HitZone
@onready var notes_container = $Notes
@onready var music_player = $MusicPlayer

const Note = preload("res://note.tscn")

# Song data
var bpm: float = 120.0
var beats_per_second: float = 2.0
var seconds_per_beat: float = 0.5
var song_start_time: float = 0.0  # In seconds
var time_begin: int = 0  # In microseconds
var notes_data: Array = []
var current_note_index: int = 0
var is_playing: bool = false

# Channel to column mapping (DTX channels to 10 columns)
var channel_to_column = {
  0x11: 0,  # Hi-Hat
  0x12: 1,  # Snare
  0x13: 2,  # Bass Drum
  0x14: 3,  # High Tom
  0x15: 4,  # Low Tom
  0x16: 5,  # Floor Tom
  0x17: 6,  # Crash
  0x18: 7,  # Ride
  0x19: 8,  # Hi-Hat Open
  0x1A: 9,  # Pedal Hi-Hat
  0x1B: 9,  # Pedal Hi-Hat (alternative)
}

# Channel to color mapping
var channel_colors = {
  0x11: Color(0.5, 0.8, 1.0),    # Hi-Hat - Light Blue
  0x12: Color(1.0, 0.3, 0.3),    # Snare - Red
  0x13: Color(0.8, 0.2, 0.8),    # Bass - Purple
  0x14: Color(1.0, 0.8, 0.2),    # High Tom - Yellow
  0x15: Color(1.0, 0.6, 0.2),    # Low Tom - Orange
  0x16: Color(0.9, 0.5, 0.1),    # Floor Tom - Dark Orange
  0x17: Color(0.3, 1.0, 0.3),    # Crash - Green
  0x18: Color(0.3, 0.8, 0.8),    # Ride - Cyan
  0x19: Color(0.7, 0.9, 1.0),    # Hi-Hat Open - Very Light Blue
  0x1A: Color(0.6, 0.7, 1.0),    # Pedal - Medium Blue
  0x1B: Color(0.6, 0.7, 1.0),    # Pedal - Medium Blue
}

func _ready():
  _setup_columns()
  _setup_hit_zone()
  _load_selected_song()

func _process(delta):
  if not is_playing or notes_data.is_empty():
    return
  
  # Get accurate audio time
  var current_time = _get_audio_time()
  
  # Spawn notes that should appear now
  while current_note_index < notes_data.size():
    var note_info = notes_data[current_note_index]
    var spawn_time = note_info.time - (SPAWN_DISTANCE / NOTE_SPEED)
    
    if current_time >= spawn_time:
      _spawn_note_from_data(note_info)
      current_note_index += 1
    else:
      break

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
  
  bpm = float(song.bpm)
  if bpm <= 0:
    bpm = 120.0
  
  beats_per_second = bpm / 60.0
  seconds_per_beat = 60.0 / bpm
  
  print("BPM: ", bpm)
  
  # Parse DTX file
  var dtx_data = _parse_dtx_file(GlobalSongData.selected_song_path)
  
  # Load background music
  if dtx_data.has("bgm_file") and not dtx_data.bgm_file.is_empty():
    _load_audio(dtx_data.bgm_file)
  
  print("Loaded ", notes_data.size(), " notes")
  
  # Start song after delay
  await get_tree().create_timer(1.0).timeout
  
  if music_player.stream != null:
    music_player.play()
    is_playing = true
    print("Music started!")
  else:
    print("No audio loaded")
    is_playing = true

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
  elif extension == "wav":
    var audio_stream = _load_wav_file(audio_path)
    if audio_stream:
      music_player.stream = audio_stream
      print("Loaded WAV file")
  elif extension == "mp3":
    var file = FileAccess.open(audio_path, FileAccess.READ)
    if file:
      var audio_stream = AudioStreamMP3.new()
      audio_stream.data = file.get_buffer(file.get_length())
      file.close()
      music_player.stream = audio_stream
      print("Loaded MP3 file")

func _load_wav_file(path: String) -> AudioStreamWAV:
  var file = FileAccess.open(path, FileAccess.READ)
  if not file:
    return null
  
  var audio_stream = AudioStreamWAV.new()
  audio_stream.data = file.get_buffer(file.get_length())
  audio_stream.format = AudioStreamWAV.FORMAT_16_BITS
  audio_stream.mix_rate = 44100
  audio_stream.stereo = true
  file.close()
  return audio_stream


func _parse_dtx_file(file_path: String) -> Dictionary:
  var result = {
    "bgm_file": "",
    "wav_map": {}
  }
  
  var file = FileAccess.open(file_path, FileAccess.READ)
  if file == null:
    return result
  
  notes_data.clear()
  var temp_notes = {}
  var dtx_dir = file_path.get_base_dir()
  
  var buffer = file.get_buffer(file.get_length())
  file.close()
  
  var content = _buffer_to_string_safe(buffer)
  var lines = content.split("\n")
  
  # Parse WAV definitions and BGM
  for line in lines:
    line = line.strip_edges()
    
    if line.is_empty() or line.begins_with(";"):
      continue
    
    if line.begins_with("#WAV"):
      var parts = line.split(":", true, 1)
      if parts.size() >= 2:
        var wav_id = parts[0].substr(4, 2)
        var wav_file = parts[1].strip_edges()
        var comment_pos = wav_file.find(";")
        if comment_pos != -1:
          wav_file = wav_file.substr(0, comment_pos).strip_edges()
        result.wav_map[wav_id] = dtx_dir + "/" + wav_file
    elif line.begins_with("#BGMWAV:"):
      var bgm_id = line.substr(8).strip_edges()
      if result.wav_map.has(bgm_id):
        result.bgm_file = result.wav_map[bgm_id]
  
  # Parse notes (rest of the function stays the same)
  for line in lines:
    line = line.strip_edges()
    
    if line.is_empty() or line.begins_with(";"):
      continue
    
    if line.begins_with("#") and line.length() > 6:
      var colon_pos = line.find(":")
      if colon_pos == -1:
        continue
      
      var header = line.substr(1, colon_pos - 1)
      var data = line.substr(colon_pos + 1).strip_edges()
      
      if header.length() >= 5:
        var measure_str = header.substr(0, 3)
        var channel_str = header.substr(3, 2)
        
        if _is_hex_string(measure_str) and _is_hex_string(channel_str):
          var measure = int("0x" + measure_str)
          var channel = int("0x" + channel_str)
          
          if channel in channel_to_column:
            _parse_measure_data(measure, channel, data, temp_notes)
  
  var note_times = temp_notes.keys()
  note_times.sort()
  
  for note_time in note_times:
    for note in temp_notes[note_time]:
      notes_data.append(note)
  
  return result
  

func _parse_measure_data(measure: int, channel: int, data: String, temp_notes: Dictionary):
  data = data.replace(" ", "").replace("\t", "")
  
  var note_count = data.length() / 2
  if note_count == 0:
    return
  
  var measure_duration = seconds_per_beat * 4.0
  var measure_start_time = measure * measure_duration
  
  for i in range(note_count):
    var note_value = data.substr(i * 2, 2)
    
    if note_value == "00":
      continue
    
    var position_in_measure = float(i) / float(note_count)
    var note_time = measure_start_time + (position_in_measure * measure_duration)
    
    var column = channel_to_column[channel]
    var color = channel_colors.get(channel, Color.WHITE)
    
    if not temp_notes.has(note_time):
      temp_notes[note_time] = []
    
    temp_notes[note_time].append({
      "time": note_time,
      "column": column,
      "color": color,
      "channel": channel
    })

func _spawn_note_from_data(note_info: Dictionary):
  var note = Note.instantiate()
  var spawn_y = HIT_ZONE_Y - SPAWN_DISTANCE
  note.position = Vector2(get_column_x_position(note_info.column), spawn_y)
  note.set_note_color(note_info.color)
  note.set_column(note_info.column)
  notes_container.add_child(note)

func _is_hex_string(s: String) -> bool:
  if s.is_empty():
    return false
  for c in s:
    if not c in "0123456789ABCDEFabcdef":
      return false
  return true

func _buffer_to_string_safe(buffer: PackedByteArray) -> String:
  var result = ""
  for i in range(buffer.size()):
    var byte = buffer[i]
    if byte < 128:
      result += char(byte)
    elif byte >= 160:
      result += char(byte)
    else:
      result += " "
  return result
