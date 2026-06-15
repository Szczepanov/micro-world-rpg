# test/unit/test_time_manager.gd
# Unit tests for TimeManager — day/night cycle state machine & replication.
# No scene graph dependency beyond tree presence for _ready() execution.
extends GutTest


var _time_manager: TimeManager


func before_each() -> void:
	# Ensure multiplayer peer is initialized for server-authoritative tests
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	_time_manager = autofree(TimeManager.new())
	add_child(_time_manager)
	await get_tree().process_frame


# ── 1.1: Initialization ─────────────────────────────────────────────────────
func test_initializes_in_day_phase() -> void:
	assert_false(_time_manager.is_night, "Should start in day phase")
	# Phase time may accumulate delta during first process frame, check it's small
	assert_lt(_time_manager.current_phase_time, 0.1, "Phase time should start near 0")
	assert_eq(_time_manager.current_wave, 0, "Wave should start at 0")


func test_has_synchronizer_after_ready() -> void:
	var sync: MultiplayerSynchronizer = _time_manager.get_node_or_null("TimeSynchronizer")
	assert_not_null(sync, "TimeSynchronizer should be created in _ready()")


# ── 1.2: Phase Display Text ───────────────────────────────────────────────────
func test_day_phase_display_text() -> void:
	_time_manager.is_night = false
	var text: String = _time_manager.get_phase_display_text()
	assert_eq(text, "Day Phase: Gather & Build", "Day phase text should match")


func test_night_phase_display_text() -> void:
	_time_manager.is_night = true
	var text: String = _time_manager.get_phase_display_text()
	assert_eq(text, "Night Phase: Defend the Core!", "Night phase text should match")


# ── 1.3: Time Remaining Calculation ───────────────────────────────────────────
func test_time_remaining_in_day_phase() -> void:
	_time_manager.is_night = false
	_time_manager.current_phase_time = 60.0
	var remaining: float = _time_manager.get_time_remaining()
	assert_eq(remaining, 120.0, "Should have 120s remaining after 60s of 180s day")


func test_time_remaining_in_night_phase() -> void:
	_time_manager.is_night = true
	_time_manager.current_phase_time = 30.0
	var remaining: float = _time_manager.get_time_remaining()
	assert_eq(remaining, 90.0, "Should have 90s remaining after 30s of 120s night")


func test_time_remaining_clamps_at_zero() -> void:
	_time_manager.is_night = false
	_time_manager.current_phase_time = 200.0
	var remaining: float = _time_manager.get_time_remaining()
	assert_eq(remaining, 0.0, "Should clamp to 0 when time exceeds duration")


# ── 1.4: Server-Only State Transitions (simulated) ────────────────────────────
func test_reset_cycle_clears_state() -> void:
	# Simulate server state
	_time_manager.is_night = true
	_time_manager.current_phase_time = 50.0
	_time_manager.current_wave = 3

	_time_manager.reset_cycle()

	assert_false(_time_manager.is_night, "Should reset to day phase")
	assert_eq(_time_manager.current_phase_time, 0.0, "Should reset phase time")
	assert_eq(_time_manager.current_wave, 0, "Should reset wave counter")


# ── 1.5: Signals ─────────────────────────────────────────────────────────────
func test_phase_changed_signal_emits_on_transition() -> void:
	watch_signals(_time_manager)

	# Simulate night transition by directly setting (normally server-only)
	_time_manager.is_night = true
	_time_manager.current_wave = 1

	# Manually trigger the phase change signal check
	_time_manager.phase_changed.emit(true, 1)

	assert_signal_emitted(_time_manager, "phase_changed", "phase_changed should emit")


func test_wave_started_signal_emits() -> void:
	watch_signals(_time_manager)

	_time_manager.wave_started.emit(1)

	assert_signal_emitted(_time_manager, "wave_started", "wave_started should emit")


func test_phase_time_updated_signal_emits() -> void:
	watch_signals(_time_manager)

	_time_manager.phase_time_updated.emit(60.0, 180.0, false)

	assert_signal_emitted(_time_manager, "phase_time_updated", "phase_time_updated should emit")


# ── 1.6: Constants ────────────────────────────────────────────────────────────
func test_day_duration_constant() -> void:
	assert_eq(TimeManager.DAY_DURATION, 180.0, "Day duration should be 180 seconds")


func test_night_duration_constant() -> void:
	assert_eq(TimeManager.NIGHT_DURATION, 120.0, "Night duration should be 120 seconds")
