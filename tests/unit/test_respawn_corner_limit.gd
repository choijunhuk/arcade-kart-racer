extends GutTest

## 19-D review: when two gates sit closer than RESPAWN_STEP_BACK + margin
## inside a tight corner, the step-back budget cannot reach straight road;
## the resolver must still pick the least-curved spot within that budget
## (never the raw apex by default, never past the previous gate).

const STRAIGHT: float = 100.0
const RADIUS: float = 15.0
const APEX_OFFSET: float = STRAIGHT + 1.0 # 1 m into the first tight arc
const GATE_GAP: float = RespawnSystem.RESPAWN_STEP_BACK + RespawnSystem.RESPAWN_PREVIOUS_GATE_MARGIN - 1.0


func _stadium() -> RacingLine:
	var line: RacingLine = RacingLine.new()
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(50.0, 0.4, -RADIUS))
	curve.add_point(Vector3(-50.0, 0.4, -RADIUS))
	for step: int in range(1, 12):
		var angle: float = deg_to_rad(-90.0 - 15.0 * float(step))
		curve.add_point(Vector3(-50.0 + RADIUS * cos(angle), 0.4, RADIUS * sin(angle)))
	curve.add_point(Vector3(-50.0, 0.4, RADIUS))
	curve.add_point(Vector3(50.0, 0.4, RADIUS))
	for step: int in range(1, 12):
		var angle: float = deg_to_rad(90.0 - 15.0 * float(step))
		curve.add_point(Vector3(50.0 + RADIUS * cos(angle), 0.4, RADIUS * sin(angle)))
	curve.add_point(Vector3(50.0, 0.4, -RADIUS))
	line.curve = curve
	add_child_autofree(line)
	return line


func _gates(line: RacingLine, offsets: Array[float]) -> Array[Checkpoint]:
	var container: Node3D = Node3D.new()
	add_child_autofree(container)
	var gates: Array[Checkpoint] = []
	for offset: float in offsets:
		var gate: Checkpoint = (load("res://track/elements/checkpoint.tscn") as PackedScene).instantiate() as Checkpoint
		container.add_child(gate)
		gate.global_position = line.sample(offset)
		gate.configure(gates.size(), line)
		gates.append(gate)
	return gates


func test_close_gates_in_a_tight_corner_pick_the_safest_spot_within_the_budget() -> void:
	var line: RacingLine = _stadium()
	var gates: Array[Checkpoint] = _gates(line, [0.0, APEX_OFFSET - GATE_GAP, APEX_OFFSET, 250.0])
	var apex: Checkpoint = gates[2]
	var raw: float = apex.offset
	assert_gt(absf(line.curvature_at(raw)), RespawnSystem.RESPAWN_MAX_CURVATURE, "fixture: gate is inside the tight corner")
	var budget: float = RespawnSystem._previous_gate_distance(apex.get_respawn_point(), line)
	assert_lt(budget, RespawnSystem.RESPAWN_STEP_BACK, "fixture: budget smaller than one step")
	var result: float = RespawnSystem.corner_safe_offset(line, raw, budget)
	assert_lt(result, raw - 0.5, "moves off the raw apex even with a sub-step budget")
	assert_gte(result - gates[1].offset, RespawnSystem.RESPAWN_PREVIOUS_GATE_MARGIN - 0.01, "never reaches the previous gate")
	assert_lt(RespawnSystem.mean_curvature_ahead(line, result), RespawnSystem.mean_curvature_ahead(line, raw))


func test_zero_budget_keeps_the_checkpoint_spot() -> void:
	var line: RacingLine = _stadium()
	var raw: float = line.offset_at(line.sample(APEX_OFFSET))
	assert_almost_eq(RespawnSystem.corner_safe_offset(line, raw, 0.0), raw, 0.01)
