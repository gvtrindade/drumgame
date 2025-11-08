# ChartParser.gd
extends Node
class_name ChartParser

# Data structures to hold parsed information
var metadata: Dictionary = {}
var wav_sounds: Dictionary = {}  # code -> {file_path, column, volume}
var notes: Array = []  # Array of {time, column, sound_code}
var bpm_changes: Dictionary = {}  # bar -> bpm value

var column_mapping: Dictionary = {
  0x11: 1, #"Closed HH" 
  0x12: 3, #"SD"
  0x13: 5, #"BD"
  0x14: 4, #"HT"
  0x15: 6, #"LT"
  0x16: 8, #"CY"
  0x17: 7, #"FT"
  0x18: 1, #"Open HH"
  0x19: 9, #"RD"
  0x1A: 0, #"LC"
  0x1B: 2, #"LP"
  0x1C: 2, #"LB"
}

var channel_mapping: Dictionary = {
  0x01: "BMG",
  0x08: "BPM",
  0x11: "CLOSED_HH",
  0x12: "SD",
  0x13: "BD",
  0x14: "HT",
  0x15: "LT",
  0x16: "CY",
  0x17: "FT",
  0x18: "OPEN_HH",
  0x19: "RD",
  0x1A: "LC",
  0x1B: "LP",
  0x1C: "LB",
}

func parse_chart_file(file_path: String) -> bool:
  var file = FileAccess.open(file_path, FileAccess.READ)
  if file == null:
    push_error("Failed to open chart file: " + file_path)
    return false
  
  var content = file.get_as_text()
  file.close()
  
  _parse_content(content)
  return true

func _parse_content(content: String) -> void:
  var lines = content.split("\n")
  
  for line in lines:
    line = line.strip_edges()
    
    # Skip empty lines and comments
    if line.is_empty() or line.begins_with(";"):
      continue
    
    # Parse different types of lines
    if line.begins_with("#WAV"):
      _parse_wav_line(line)
    elif line.begins_with("#VOLUME"):
      _parse_volume_line(line)
    elif _is_note_line(line):
      _parse_note_line(line)
    else:
      _parse_metadata_line(line)

func _parse_wav_line(line: String) -> void:
  # Format: #WAV<code>: <file_path>;<column_code>
  # or: #WAV<code>: <file_path>\t;<description>
  var parts = line.split(":", true, 1)
  if parts.size() < 2:
    return
  
  var code = parts[0].replace("#WAV", "").strip_edges()
  var right_side = parts[1].strip_edges()
  
  # Split by semicolon or tab+semicolon
  var file_and_column = right_side.split(";")
  var file_path = file_and_column[0].strip_edges()
  
  # Initialize sound data
  if not wav_sounds.has(code):
    wav_sounds[code] = {
      "file_path": file_path,
      "column": "",
      "volume": 100
    }
  else:
    wav_sounds[code]["file_path"] = file_path
  
  # Check if column mapping is provided after semicolon
  if file_and_column.size() > 1:
    var column_code = file_and_column[1].strip_edges()
    # Remove any additional comments
    if "\t" in column_code:
      column_code = column_code.split("\t")[0].strip_edges()
    if not column_code.is_empty() and column_code.length() <= 2:
      wav_sounds[code]["column"] = column_code

func _parse_volume_line(line: String) -> void:
  # Format: #VOLUME<code>: <volume>
  var parts = line.split(":", true, 1)
  if parts.size() < 2:
    return
  
  var code = parts[0].replace("#VOLUME", "").strip_edges()
  var volume = int(parts[1].strip_edges())
  
  if wav_sounds.has(code):
    wav_sounds[code]["volume"] = volume

func _parse_bpm_line(line: String) -> void:
  # Format: #BPM: <value> or #BPM<code>: <value>
  var parts = line.split(":", true, 1)
  if parts.size() < 2:
    return
  
  var key = parts[0].replace("#BPM", "").strip_edges()
  var value = float(parts[1].strip_edges())
  
  if key.is_empty():
    # Base BPM
    metadata["bpm"] = value
  else:
    # BPM change at specific point
    bpm_changes[key] = value

func _is_note_line(line: String) -> bool:
  # Note lines start with # followed by bar number (3-5 digits) and channel (2 hex digits)
  # Format: #<bar><channel>: <data>
  if not line.begins_with("#"):
    return false

  var parts = line.split(":", true, 1)
  var regex = RegEx.new()
  regex.compile("^\\#\\d{4}[a-zA-Z0-9]+$") 
  return regex.search(parts[0]) != null

func _parse_note_line(line: String) -> void:
  # Format: #<bar><channel>: <note_data>
  # Example: #00313: 02 means at bar 003, channel 13, sound code 02
  var parts = line.split(":", true, 1)
  if parts.size() < 2:
    return
  
  var identifier = parts[0].substr(1)  # Remove #
  var note_data = parts[1].strip_edges()
  
  if note_data.is_empty() or note_data == "00":
    return
  
  # Extract bar and channel
  var bar = int(identifier.substr(0, 3))
  var channel = identifier.substr(3)
  
  # Parse note data (pairs of hex characters)
  var note_count = note_data.length() / 2
  var time_division = 1.0 / float(note_count)
  
  for i in range(note_count):
    var sound_code = note_data.substr(i * 2, 2)
    var channel_hex =  "0x" + channel
    if sound_code != "00":
      var time = float(bar) + (float(i) * time_division)
      var is_channel_column = column_mapping.keys().has(channel_hex.hex_to_int())
           
      notes.append({
        "time": time,
        "bar": bar,
        "position": float(i) * time_division,
        "column": column_mapping[channel_hex.hex_to_int()] if is_channel_column else null,
        "sound_code": sound_code,
        "channel": channel_hex
      })

func _parse_metadata_line(line: String) -> void:
  # Format: #KEY: value
  if not line.begins_with("#"):
    return
  
  var parts = line.split(":", true, 1)
  if parts.size() < 2:
    return
  
  var key = parts[0].substr(1).strip_edges().to_lower()
  var value = parts[1].strip_edges()
  
  metadata[key] = value

# Helper functions to get parsed data
func get_metadata() -> Dictionary:
  return metadata

func get_wav_sounds() -> Dictionary:
  return wav_sounds

func get_notes() -> Array:
  return notes

func get_bpm_changes() -> Dictionary:
  return bpm_changes

func get_column_mapping() -> Dictionary:
  return column_mapping

# Convert bar time to actual seconds
func bar_to_seconds(bar_time: float, bpm_value: float = 120.0) -> float:
  if metadata.has("bpm"):
    bpm_value = float(metadata["bpm"])
  
  var seconds_per_bar = (60.0 / bpm_value) * 4.0  # Assuming 4/4 time
  
  # TODO: Account for BPM changes
  return bar_time * seconds_per_bar


# Get all notes sorted by time
func get_sorted_notes() -> Array:
  var sorted = notes.duplicate()
  sorted.sort_custom(func(a, b): return a.time < b.time)
  return sorted
