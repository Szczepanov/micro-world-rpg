# test/unit/test_health_component.gd
# Unit tests for HealthComponent — server-authoritative combat math.
# No scene graph dependency; HealthComponent is a pure Node subclass.
extends GutTest


var _hc: HealthComponent


func before_each() -> void:
	# autofree() registers the node for cleanup after each test.
	_hc = autofree(HealthComponent.new())
	# max_health defaults to 100.0 — verified in first test.
	# Add to tree so _ready() fires (_setup_synchronizer is server-only
	# and safe to call in headless mode).
	add_child(_hc)
	await get_tree().process_frame


# ── 4.1: Initialization ───────────────────────────────────────────────────────
func test_health_initializes_at_max() -> void:
	assert_eq(
		_hc.current_health,
		_hc.max_health,
		"current_health must equal max_health immediately after _ready()"
	)
	assert_eq(_hc.max_health, 100.0, "Default max_health must be 100.0")


# ── 4.2: Damage reduces health correctly ──────────────────────────────────────
func test_request_damage_reduces_health() -> void:
	watch_signals(_hc)

	_hc.request_damage(25.0)
	await get_tree().process_frame

	assert_eq(
		_hc.current_health,
		75.0,
		"25 damage from 100 HP must leave exactly 75 HP"
	)
	assert_signal_emitted(
		_hc,
		"health_changed",
		"health_changed must fire after damage"
	)


# ── 4.3: health_changed carries correct payload ───────────────────────────────
func test_health_changed_signal_carries_correct_values() -> void:
	watch_signals(_hc)

	_hc.request_damage(30.0)
	await get_tree().process_frame

	# GUT records emissions as arrays of argument arrays.
	# assert_signal_emitted_with_parameters checks the last emission.
	assert_signal_emitted_with_parameters(
		_hc,
		"health_changed",
		[70.0, 100.0],
		"health_changed(new_health, max_health) must carry [70.0, 100.0]"
	)


# ── 4.4: Health cannot go below zero ─────────────────────────────────────────
func test_overkill_damage_clamps_to_zero() -> void:
	_hc.request_damage(999.0)
	await get_tree().process_frame

	assert_eq(
		_hc.current_health,
		0.0,
		"current_health must clamp to 0 on overkill damage"
	)


# ── 4.5: died signal fires on lethal hit ─────────────────────────────────────
func test_lethal_damage_fires_died_signal() -> void:
	watch_signals(_hc)

	_hc.request_damage(100.0)
	await get_tree().process_frame

	assert_signal_emitted(_hc, "died", "'died' must emit when health reaches 0")


# ── 4.6: died signal does NOT double-fire ────────────────────────────────────
## Regression: if request_damage() is called twice while already at 0 HP,
## the setter's old_health guard (health_component.gd:12) must prevent a
## second 'died' emission because current_health is already 0.0 == new_val.
func test_died_signal_does_not_double_fire() -> void:
	watch_signals(_hc)

	# First lethal hit
	_hc.request_damage(100.0)
	await get_tree().process_frame

	# Second call on a dead entity (e.g. turret fires again before cleanup)
	_hc.request_damage(50.0)
	await get_tree().process_frame

	assert_signal_emit_count(
		_hc,
		"died",
		1,
		"'died' must fire exactly once, even if damage is applied to a dead entity"
	)


# ── 4.7: Healing restores health ─────────────────────────────────────────────
func test_request_healing_increases_health() -> void:
	_hc.current_health = 40.0  # Direct setter for setup

	watch_signals(_hc)
	_hc.request_healing(30.0)
	await get_tree().process_frame

	assert_eq(_hc.current_health, 70.0, "Healing 30 from 40 must give 70")
	assert_signal_emitted(_hc, "health_changed", "health_changed fires on heal")


# ── 4.8: Healing does not exceed max_health ───────────────────────────────────
func test_healing_clamps_at_max_health() -> void:
	_hc.current_health = 90.0
	_hc.request_healing(50.0)
	await get_tree().process_frame

	assert_eq(
		_hc.current_health,
		100.0,
		"Overhealing must clamp at max_health (100.0)"
	)
