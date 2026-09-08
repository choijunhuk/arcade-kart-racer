extends GutTest

const POOL_PATH: String = "res://core/object_pool.gd"


func test_pool_script_exists() -> void:
	assert_true(ResourceLoader.exists(POOL_PATH))


func test_released_instance_is_reused_before_a_new_one_is_created() -> void:
	var pool: RefCounted = _make_pool()
	if pool == null:
		return
	var template: Node3D = Node3D.new()
	template.name = "PooledTemplate"
	var scene: PackedScene = PackedScene.new()
	assert_eq(scene.pack(template), OK)
	template.free()
	var parent: Node = Node.new()
	add_child_autofree(parent)
	pool.call("configure", scene, parent, 2)
	var first: Node = pool.call("acquire") as Node
	pool.call("release", first)
	var second: Node = pool.call("acquire") as Node
	assert_same(second, first)
	assert_eq(int(pool.call("get_active_count")), 1)
	assert_eq(int(pool.call("get_available_count")), 0)


func test_pool_refuses_to_exceed_capacity() -> void:
	var pool: RefCounted = _make_pool()
	if pool == null:
		return
	var template: Node3D = Node3D.new()
	var scene: PackedScene = PackedScene.new()
	assert_eq(scene.pack(template), OK)
	template.free()
	var parent: Node = Node.new()
	add_child_autofree(parent)
	pool.call("configure", scene, parent, 1)
	assert_not_null(pool.call("acquire"))
	assert_null(pool.call("acquire"))


func _make_pool() -> RefCounted:
	if not ResourceLoader.exists(POOL_PATH):
		fail_test("ObjectPool script is missing")
		return null
	return (load(POOL_PATH) as GDScript).new() as RefCounted
