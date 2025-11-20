class_name SongMetadata
extends Resource

@export var file_path: String
@export var title: String = "Unknown"
@export var artist: String = "Unknown"
@export var genre: String = ""
@export var bpm: String = "0"
@export var dlevel: String = "0"
@export var preview: String = ""
@export var preimage: String = ""

func get_display_name() -> String:
    return "%s - %s" % [title, artist]