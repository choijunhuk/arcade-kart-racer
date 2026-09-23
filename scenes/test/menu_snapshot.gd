extends Node
## Windowed visual review tool for the menu flow (not headless). Boots each
## menu screen in turn as a real scene (autoloads live, DebugOverlay hidden,
## automation_mode on so the first-run tutorial prompt never covers it), waits
## for its intro animation to settle and saves one PNG per screen.
## usage: godot --path . --resolution 1600x900 res://scenes/test/menu_snapshot.tscn -- <out_dir> [settle_seconds] [name_filter_csv]
## example: ... -- /tmp/menus 1.6 main_menu,track_select

const SCREENS: Array[String] = [
	"res://ui/menus/main_menu.tscn",
	"res://ui/menus/mode_select.tscn",
	"res://ui/menus/driver_select.tscn",
	"res://ui/menus/kart_select.tscn",
	"res://ui/menus/track_select.tscn",
	"res://ui/menus/difficulty_select.tscn",
	"res://ui/menus/settings_menu.tscn",
	"res://ui/menus/local_lobby.tscn",
	"res://ui/menus/online_lobby.tscn",
	"res://ui/components/loading_screen.tscn",
	"res://ui/components/transition_overlay.tscn",
]
const DEFAULT_SETTLE_SECONDS: float = 1.6

var _out_dir: String = "/tmp/menus"
var _settle_seconds: float = DEFAULT_SETTLE_SECONDS
var _queue: Array[String] = []


func _ready() -> void:
	GameState.automation_mode = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else _out_dir
	_settle_seconds = float(args[1]) if args.size() > 1 else DEFAULT_SETTLE_SECONDS
	var filter: PackedStringArray = args[2].split(",", false) if args.size() > 2 else PackedStringArray()
	for path: String in SCREENS:
		if filter.is_empty() or filter.has(path.get_file().get_basename()):
			_queue.append(path)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var overlay: Node = get_node_or_null(^"/root/DebugOverlay")
	if overlay != null:
		overlay.set("visible", false)
	_run.call_deferred()


func _run() -> void:
	for path: String in _queue:
		var screen: Node = (load(path) as PackedScene).instantiate()
		add_child(screen)
		if screen is TransitionOverlay:
			# Freeze the wipe mid-sweep over the main menu for review.
			var under: Node = (load(SCREENS[0]) as PackedScene).instantiate()
			add_child(under)
			move_child(under, 0)
			screen.tree_exited.connect(under.queue_free)
			screen.visible = true
			(screen.get_node(^"Fade") as ColorRect).modulate.a = 0.55
		await get_tree().create_timer(_settle_seconds).timeout
		await RenderingServer.frame_post_draw
		var out: String = "%s/%s.png" % [_out_dir, path.get_file().get_basename()]
		get_viewport().get_texture().get_image().save_png(out)
		print("SNAPSHOT %s" % out)
		screen.queue_free()
		await get_tree().process_frame
	get_tree().quit()
