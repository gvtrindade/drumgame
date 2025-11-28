extends Control

@onready var scroll_container = $ScrollContainer
@onready var content = $ScrollContainer/Content
@onready var title_label = $TitleBar/Title
@onready var back_button = $TitleBar/BackButton
@onready var chart_parser = ChartParser.new()

# Visual constants
const COLUMN_WIDTH = 60
const BAR_HEIGHT = 200 # Height of one bar (96 positions)
const POSITION_HEIGHT = BAR_HEIGHT / 96.0 # Height per position unit
const MARGIN_LEFT = 50
const MARGIN_TOP = 50
const NOTE_SIZE = Vector2(50, 10)

# Column layout: BGM | BPM | 10 drum columns
const TOTAL_COLUMNS = 12 # 2 special + 10 drums
const BGM_COLUMN = 0
const BPM_COLUMN = 1
const DRUM_COLUMN_OFFSET = 2

var max_bar = 0
var chart_loaded = false

func _ready():
  # Set up the chart parser
  add_child(chart_parser)
  
  if GlobalSongData.selected_song_path != "":
    load_chart()

func load_chart():
  var file_path = GlobalSongData.selected_song_path
  
  if file_path == "":
    push_error("No song selected in GlobalSongData")
    return
  
  if not chart_parser.parse_chart_file(file_path):
    push_error("Failed to load chart: " + file_path)
    return
  
  chart_loaded = true
  _visualize_chart()

func _visualize_chart():
  # Clear previous content
  for child in content.get_children():
    child.queue_free()
  
  # Find the maximum bar number
  max_bar = 0
  for note in chart_parser.notes:
    if note.bar > max_bar:
      max_bar = note.bar
  
  # Set content size
  var content_width = MARGIN_LEFT * 2 + TOTAL_COLUMNS * COLUMN_WIDTH
  var content_height = MARGIN_TOP * 2 + (max_bar + 1) * BAR_HEIGHT
  content.custom_minimum_size = Vector2(content_width, content_height)
  
  # Draw background and grid
  _draw_grid()
  
  # Draw bar lines
  _draw_bar_lines()
  
  # Draw notes
  _draw_notes()
  
  # Draw BGM and BPM markers
  _draw_special_channels()
  
  # Add these lines to scroll to bottom automatically:
  await get_tree().process_frame
  scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)


func _draw_grid():
  # Draw column separators and labels
  for col in range(TOTAL_COLUMNS):
    var x_pos = MARGIN_LEFT + col * COLUMN_WIDTH
    
    # Column label at the bottom
    var label = Label.new()
    if col == BGM_COLUMN:
      label.text = "BGM"
    elif col == BPM_COLUMN:
      label.text = "BPM"
    else:
      var drum_col = col - DRUM_COLUMN_OFFSET
      label.text = _get_drum_name(drum_col)
    
    # Change from top to bottom:
    label.position = Vector2(x_pos + 5, content.custom_minimum_size.y - 25)
    label.add_theme_font_size_override("font_size", 10)
    content.add_child(label)
    
    # Column separator line
    var line = Line2D.new()
    line.add_point(Vector2(x_pos, MARGIN_TOP))
    line.add_point(Vector2(x_pos, content.custom_minimum_size.y - MARGIN_TOP))
    line.default_color = Color(0.3, 0.3, 0.3, 0.5)
    line.width = 1
    content.add_child(line)


func _draw_bar_lines():
  # Draw bar lines at various positions with different weights
  for bar in range(max_bar + 1):
    # Draw all subdivision lines (every 6 positions)
    for bar_position in [0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72, 78, 84, 90]:
      # Invert the y calculation - bar 0 at bottom:
      var y_pos = content.custom_minimum_size.y - MARGIN_TOP - (bar * BAR_HEIGHT + bar_position * POSITION_HEIGHT)
      
      # Determine line style based on position
      var line_width = 1.0
      var line_color = Color(0.5, 0.5, 0.5, 0.5)
      
      if bar_position == 0:
        # Major bar line (position 0)
        line_width = 3.0
        line_color = Color(0.8, 0.8, 0.8, 1.0)
      elif bar_position == 24 or bar_position == 48 or bar_position == 72:
        # Quarter note lines (positions 24, 48, 72)
        line_width = 1.5
        line_color = Color(0.5, 0.5, 0.5, 0.5)
      else:
        # Subdivision lines (positions 6, 12, 18, 30, 36, 42, 54, 60, 66, 78, 84, 90)
        line_width = 0.5
        line_color = Color(0.4, 0.4, 0.4, 0.3)
      
      var line = Line2D.new()
      line.add_point(Vector2(MARGIN_LEFT, y_pos))
      line.add_point(Vector2(MARGIN_LEFT + TOTAL_COLUMNS * COLUMN_WIDTH, y_pos))
      line.default_color = line_color
      line.width = line_width
      
      content.add_child(line)
      
      # Add bar number label at position 0
      if bar_position == 0:
        var bar_label = Label.new()
        bar_label.text = str(bar)
        bar_label.position = Vector2(10, y_pos - 10)
        bar_label.add_theme_font_size_override("font_size", 12)
        content.add_child(bar_label)


func _draw_notes():
  # Draw regular drum notes
  for note in chart_parser.notes:
    if note.column == null:
      continue # Skip BGM/BPM notes (handled separately)
    
    var col = note.column + DRUM_COLUMN_OFFSET
    var x_pos = MARGIN_LEFT + col * COLUMN_WIDTH + (COLUMN_WIDTH - NOTE_SIZE.x) / 2
    # Invert the y calculation:
    var y_pos = content.custom_minimum_size.y - MARGIN_TOP - (note.bar * BAR_HEIGHT + note.position * POSITION_HEIGHT)
    
    var note_visual = ColorRect.new()
    note_visual.size = NOTE_SIZE
    note_visual.position = Vector2(x_pos, y_pos - NOTE_SIZE.y / 2)
    note_visual.color = note.color
    content.add_child(note_visual)


func _draw_special_channels():
  # Draw BGM and BPM markers
  for note in chart_parser.notes:
    var channel_int = note.channel.hex_to_int()
    
    var col = -1
    if channel_int == 0x01: # BGM
      col = BGM_COLUMN
    elif channel_int == 0x08: # BPM
      col = BPM_COLUMN
    
    if col >= 0:
      var x_pos = MARGIN_LEFT + col * COLUMN_WIDTH + (COLUMN_WIDTH - NOTE_SIZE.x) / 2
      # Invert the y calculation:
      var y_pos = content.custom_minimum_size.y - MARGIN_TOP - (note.bar * BAR_HEIGHT + note.position * POSITION_HEIGHT)
      
      var marker = ColorRect.new()
      marker.size = NOTE_SIZE
      marker.position = Vector2(x_pos, y_pos - NOTE_SIZE.y / 2)
      
      if channel_int == 0x01:
        marker.color = Color(0.2, 1.0, 0.2, 0.8) # Green for BGM
      else:
        marker.color = Color(1.0, 1.0, 0.2, 0.8) # Yellow for BPM
      
      content.add_child(marker)


func _get_drum_name(column: int) -> String:
  match column:
    0: return "LC"
    1: return "HH"
    2: return "LP"
    3: return "SD"
    4: return "HT"
    5: return "BD"
    6: return "LT"
    7: return "FT"
    8: return "CY"
    9: return "RD"
    _: return ""

func _on_back_button_pressed():
  SceneManager.goto_scene("song_select")
