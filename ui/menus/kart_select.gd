class_name KartSelectMenu
extends MenuScreen

const KART_DIRECTORY: String = "res://data/karts"
const TRACK_SELECT_PATH: String = "res://ui/menus/track_select.tscn"
const GRID_COLUMNS: int = 3
const CARD_SIZE: Vector2 = Vector2(285.0, 330.0)
const CARD_CONTENT_MARGIN: int = 12
const PREVIEW_HEIGHT: float = 82.0
const STAT_BAR_SCENE: PackedScene = preload("res://ui/components/stat_bar.tscn")
const STAT_RANGES: Dictionary = {
	"max_speed": Vector2(24.0, 32.0),
	"acceleration": Vector2(10.0, 18.0),
	"handling": Vector2(0.7, 1.3),
	"drift_factor": Vector2(0.7, 1.3),
	"weight": Vector2(0.6, 1.5),
}

@onready var _grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var _back_button: Button = $Panel/VBox/BackButton

var _buttons: Array[Control] = []


func _ready() -> void:
	super._ready()
	_build_kart_grid()
	_back_button.pressed.connect(go_back)
	if not _buttons.is_empty():
		wire_grid_focus(_buttons, GRID_COLUMNS)
		focus_initial(_buttons[0])


func _build_kart_grid() -> void:
	for resource: Resource in ResourceScanner.scan_tres(KART_DIRECTORY):
		if not resource is KartData:
			continue
		var kart: KartData = resource as KartData
		var button: Button = _create_kart_card(kart)
		button.pressed.connect(_select_kart.bind(kart))
		_grid.add_child(button)
		_buttons.append(button)


func _create_kart_card(kart: KartData) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.text = ""
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, CARD_CONTENT_MARGIN)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var preview: ColorRect = ColorRect.new()
	preview.custom_minimum_size.y = PREVIEW_HEIGHT
	preview.color = kart.body_color
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(preview)
	var name_label: Label = Label.new()
	name_label.text = kart.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	var stats: VBoxContainer = VBoxContainer.new()
	stats.name = "Stats"
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(stats)
	for stat_name: String in STAT_RANGES:
		var range_value: Vector2 = STAT_RANGES[stat_name]
		var normalized: float = inverse_lerp(range_value.x, range_value.y, float(kart.get(stat_name)))
		var bar: StatBar = STAT_BAR_SCENE.instantiate() as StatBar
		stats.add_child(bar)
		bar.configure(stat_name.replace("_", " ").to_upper(), normalized)
	return button


func _select_kart(kart: KartData) -> void:
	GameState.selected_kart_id = kart.id
	go_to(TRACK_SELECT_PATH)
