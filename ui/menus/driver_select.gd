class_name DriverSelectMenu
extends MenuScreen

const DRIVER_DIRECTORY: String = "res://data/drivers"
const KART_SELECT_PATH: String = "res://ui/menus/kart_select.tscn"
const GRID_COLUMNS: int = 4
const CARD_SIZE: Vector2 = Vector2(230.0, 210.0)
const CARD_CONTENT_MARGIN: int = 10
const PORTRAIT_HEIGHT: float = 64.0
const MIN_DRIVER_MODIFIER: float = -0.05
const DRIVER_MODIFIER_SPAN: float = 0.1
const PERCENT_SCALE: float = 100.0
const STAT_BAR_SCENE: PackedScene = preload("res://ui/components/stat_bar.tscn")

@onready var _grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var _back_button: Button = $Panel/VBox/BackButton

var _buttons: Array[Control] = []


func _ready() -> void:
	super._ready()
	_build_driver_grid()
	_back_button.pressed.connect(go_back)
	if not _buttons.is_empty():
		wire_grid_focus(_buttons, GRID_COLUMNS)
		focus_initial(_buttons[0])


func _build_driver_grid() -> void:
	for resource: Resource in ResourceScanner.scan_tres(DRIVER_DIRECTORY):
		if not resource is DriverData:
			continue
		var driver: DriverData = resource as DriverData
		var button: Button = _create_driver_card(driver)
		button.pressed.connect(_select_driver.bind(driver))
		_grid.add_child(button)
		_buttons.append(button)


func _create_driver_card(driver: DriverData) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.text = ""
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, CARD_CONTENT_MARGIN)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var portrait: ColorRect = ColorRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size.y = PORTRAIT_HEIGHT
	portrait.color = driver.driver_color
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(portrait)
	var name_label: Label = Label.new()
	name_label.text = driver.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	var stats: VBoxContainer = VBoxContainer.new()
	stats.name = "Stats"
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(stats)
	for stat_name: StringName in driver.stat_mods:
		var bar: StatBar = STAT_BAR_SCENE.instantiate() as StatBar
		var modifier: float = driver.stat_mods[stat_name]
		stats.add_child(bar)
		bar.configure(
			String(stat_name).replace("_", " ").to_upper(),
			(modifier - MIN_DRIVER_MODIFIER) / DRIVER_MODIFIER_SPAN,
			"%+.0f%%" % (modifier * PERCENT_SCALE),
		)
	return button


func _select_driver(driver: DriverData) -> void:
	GameState.selected_driver_id = driver.id
	go_to(KART_SELECT_PATH)
