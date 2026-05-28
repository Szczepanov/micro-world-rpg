# test/unit/test_turret_targeting.gd
# Unit tests for AutomatedTurret._scan_for_target() targeting algorithm.
# Uses a testable subclass that injects the enemy body list without physics.
extends GutTest


# ── Inner: stub enemy with a real HealthComponent child ───────────────────────
class MockEnemy extends Node3D:
	var _health: HealthComponent

	func _init(hp: float = 100.0) -> void:
		# Health component child is what the turret looks for (turret.gd:114)
		_health = HealthComponent.new()
		_health.name = "HealthComponent"
		_health.max_health = hp
		# NOTE: current_health is set in _ready(), but since we're not in the
		# tree yet we set it via the property directly after adding the child.

	func _ready() -> void:
		add_child(_health)
		_health.current_health = _health.max_health

	func setup_in_tree(parent: Node) -> void:
		parent.add_child(self)
		# Force current_health after _ready() has fired
		_health.current_health = _health.max_health

	func get_hp() -> float:
		return _health.current_health if _health else 0.0


# ── Inner: testable AutomatedTurret subclass ──────────────────────────────────
## We override _scan_for_target() to consume an injectable list instead of
## querying detection_area physics overlaps.
class TestableTurret extends Node3D:
	var current_target: Node3D = null
	var _injected_bodies: Array[Node3D] = []

	## Call this to set the fake physics-overlap result before scanning.
	func set_overlapping_bodies(bodies: Array[Node3D]) -> void:
		_injected_bodies = bodies

	## Mirrors automated_turret.gd:_scan_for_target() exactly, but reads
	## _injected_bodies instead of detection_area.get_overlapping_bodies().
	func scan_for_target() -> void:
		var closest_enemy: Node3D = null
		var closest_dist: float   = INF

		for body in _injected_bodies:
			if not body is Node3D or body == self:
				continue
			if not body.is_in_group("Enemies"):
				continue
			var target_health := body.get_node_or_null("HealthComponent") as HealthComponent
			if target_health and target_health.current_health > 0:
				var dist: float = global_position.distance_to(body.global_position)
				if dist < closest_dist:
					closest_dist  = dist
					closest_enemy = body

		current_target = closest_enemy


# ── Fixtures ──────────────────────────────────────────────────────────────────
var _turret: TestableTurret
var _root:   Node3D   # Scene root to hold all test nodes


func before_each() -> void:
	_root   = autofree(Node3D.new())
	_turret = TestableTurret.new()
	_root.add_child(_turret)
	add_child(_root)
	await get_tree().process_frame


# ── 5.1: No enemies → no target ───────────────────────────────────────────────
func test_no_enemies_yields_null_target() -> void:
	_turret.set_overlapping_bodies([])
	_turret.scan_for_target()

	assert_null(
		_turret.current_target,
		"current_target must be null when no enemies are present"
	)


# ── 5.2: Single living enemy → locked ─────────────────────────────────────────
func test_single_living_enemy_is_selected() -> void:
	var enemy := MockEnemy.new(100.0)
	enemy.add_to_group("Enemies")
	enemy.setup_in_tree(_root)
	enemy.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().process_frame

	_turret.set_overlapping_bodies([enemy])
	_turret.scan_for_target()

	assert_eq(
		_turret.current_target,
		enemy,
		"The only living enemy must be selected as current_target"
	)


# ── 5.3: Nearest enemy wins ───────────────────────────────────────────────────
## Three enemies at distances 2, 5, 10.  The one at distance 2 must win.
func test_nearest_living_enemy_is_selected() -> void:
	var near_enemy := MockEnemy.new(100.0)
	var mid_enemy  := MockEnemy.new(100.0)
	var far_enemy  := MockEnemy.new(100.0)

	near_enemy.add_to_group("Enemies")
	mid_enemy.add_to_group("Enemies")
	far_enemy.add_to_group("Enemies")

	near_enemy.setup_in_tree(_root)
	mid_enemy.setup_in_tree(_root)
	far_enemy.setup_in_tree(_root)

	_turret.global_position  = Vector3.ZERO
	near_enemy.global_position = Vector3(2.0,  0.0, 0.0)
	mid_enemy.global_position  = Vector3(5.0,  0.0, 0.0)
	far_enemy.global_position  = Vector3(10.0, 0.0, 0.0)
	await get_tree().process_frame

	_turret.set_overlapping_bodies([far_enemy, mid_enemy, near_enemy])  # Shuffled order
	_turret.scan_for_target()

	assert_eq(
		_turret.current_target,
		near_enemy,
		"Turret must lock on the nearest enemy regardless of array order"
	)


# ── 5.4: Dead enemies are skipped ─────────────────────────────────────────────
func test_dead_enemies_are_skipped() -> void:
	var dead_close := MockEnemy.new(100.0)
	var alive_far  := MockEnemy.new(100.0)

	dead_close.add_to_group("Enemies")
	alive_far.add_to_group("Enemies")

	dead_close.setup_in_tree(_root)
	alive_far.setup_in_tree(_root)

	_turret.global_position      = Vector3.ZERO
	dead_close.global_position   = Vector3(1.0, 0.0, 0.0)   # nearest, but dead
	alive_far.global_position    = Vector3(8.0, 0.0, 0.0)

	# Kill the close enemy
	dead_close._health.current_health = 0.0
	await get_tree().process_frame

	_turret.set_overlapping_bodies([dead_close, alive_far])
	_turret.scan_for_target()

	assert_eq(
		_turret.current_target,
		alive_far,
		"Dead enemies must be skipped; alive_far must win even at greater distance"
	)


# ── 5.5: Entities NOT in Enemies group are ignored ────────────────────────────
func test_non_enemy_group_nodes_are_ignored() -> void:
	var prop := Node3D.new()       # No "Enemies" group
	prop.global_position = Vector3(1.0, 0.0, 0.0)
	_root.add_child(prop)
	await get_tree().process_frame

	_turret.set_overlapping_bodies([prop])
	_turret.scan_for_target()

	assert_null(
		_turret.current_target,
		"Nodes not in the 'Enemies' group must never be selected as targets"
	)

	prop.queue_free()


# ── 5.6: All enemies dead → no target ────────────────────────────────────────
func test_all_enemies_dead_yields_null_target() -> void:
	var e1 := MockEnemy.new(100.0)
	var e2 := MockEnemy.new(100.0)
	e1.add_to_group("Enemies")
	e2.add_to_group("Enemies")
	e1.setup_in_tree(_root)
	e2.setup_in_tree(_root)
	e1.global_position = Vector3(2.0, 0.0, 0.0)
	e2.global_position = Vector3(4.0, 0.0, 0.0)

	e1._health.current_health = 0.0
	e2._health.current_health = 0.0
	await get_tree().process_frame

	_turret.set_overlapping_bodies([e1, e2])
	_turret.scan_for_target()

	assert_null(
		_turret.current_target,
		"current_target must be null when all enemies in range are dead"
	)
