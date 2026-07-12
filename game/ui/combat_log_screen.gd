class_name CombatLogScreen
extends Control

## The raid-night show (M4-003, reworked by MI-004).
##
## The engine's data was already rich; the feed was flat — every beat rendered at
## the same weight, so the player read a spreadsheet and could not feel the moment
## a pull turned, or tell that this attempt was CLOSER than the last. That is a
## presentation failure, not an engine one.
##
## This screen is still a thin renderer — it invents no numbers. It:
##   * keeps the fight legible while it runs (phase, raiders alive, furthest yet),
##   * paces the feed so beats LAND instead of dumping,
##   * weights every line by PullContracts.notability_for() — routine recedes,
##     decisive shouts,
##   * turns phase changes into beats rather than more log lines,
##   * and closes each pull with a card that answers the only question that
##     matters on a wipe: *were we closer?*
##
## Contract: docs/guildmaster-presentation.md.

const REVEAL_SECONDS := 0.45  # one beat per this many seconds at 1x
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

var _campaign: Dictionary = {}
var _prep: Dictionary = {}
var _shell: Node
var _bosses: Array[String] = []
var _boss_index := 0
var _attempt := 1
var _history: Array[Dictionary] = []

## The PREVIOUS best progress per boss — the baseline "were we closer?" compares
## against. Updated only AFTER a pull is scored, or the answer is always "no".
var _best_pct: Dictionary = {}

# live pull state
var _queue: Array[Dictionary] = []
var _alive := 0
var _roster := 0
var _pending: Dictionary = {}
var _speed_index := 0
var _instant := false

var _timer: Timer
var _boss_label: Label
var _phase_label: Label
var _alive_label: Label
var _best_label: Label
var _feed: VBoxContainer
var _scroll: ScrollContainer
var _outcome_card: PanelContainer
var _pull_button: Button
var _speed_button: Button
var _instant_button: Button
var _skip_button: Button
var _next_button: Button
var _end_button: Button


func setup(campaign: Dictionary, prep: Dictionary, shell: Node) -> void:
	_campaign = campaign
	_prep = prep
	_shell = shell
	_bosses = NightRunner.encounter_slugs(campaign["db"], int(campaign["event_id"]))
	_build_layout()
	_refresh_status()


# --- layout -------------------------------------------------------------------


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	root.add_child(_build_status_strip())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed.add_theme_constant_override("separation", 3)
	_scroll.add_child(_feed)

	_outcome_card = PanelContainer.new()
	_outcome_card.visible = false
	root.add_child(_outcome_card)

	root.add_child(_build_controls())

	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_reveal_next)
	add_child(_timer)


## What stays true while the pull runs. Everything here is a fact the engine
## actually produces — there is no simulated boss-health bar, because the engine
## does not model boss HP over time (it derives final progress from the DPS
## margin). Faking a draining bar would be the feed lying about the sim.
func _build_status_strip() -> PanelContainer:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	_boss_label = Label.new()
	_boss_label.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
	row.add_child(_boss_label)

	_phase_label = Label.new()
	_phase_label.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	row.add_child(_phase_label)

	_alive_label = Label.new()
	row.add_child(_alive_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_best_label = Label.new()
	_best_label.add_theme_color_override("font_color", ThemeBuilder.TRIUMPH)
	row.add_child(_best_label)
	return panel


func _build_controls() -> HBoxContainer:
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)

	_pull_button = Button.new()
	_pull_button.text = "Pull"
	_pull_button.pressed.connect(_on_pull)
	controls.add_child(_pull_button)

	_skip_button = Button.new()
	_skip_button.text = "Skip to result"
	_skip_button.pressed.connect(_on_skip_to_result)
	controls.add_child(_skip_button)

	_speed_button = Button.new()
	_speed_button.pressed.connect(_on_cycle_speed)
	controls.add_child(_speed_button)

	_instant_button = Button.new()
	_instant_button.pressed.connect(_on_toggle_instant)
	controls.add_child(_instant_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)

	_next_button = Button.new()
	_next_button.text = "Skip to next boss"
	_next_button.pressed.connect(_on_skip_boss)
	controls.add_child(_next_button)

	_end_button = Button.new()
	_end_button.text = "End night → Report"
	_end_button.pressed.connect(_on_end_night)
	controls.add_child(_end_button)

	_sync_pacing_buttons()
	return controls


# --- pulling ------------------------------------------------------------------


func _on_pull() -> void:
	if _boss_index >= _bosses.size() or _is_revealing():
		return
	var slug := _bosses[_boss_index]
	var step := NightRunner.resolve_pull(
		_campaign["db"],
		int(_campaign["seed"]),
		int(_campaign["guild_id"]),
		int(_campaign["event_id"]),
		_prep,
		slug,
		_attempt
	)
	if not bool(step.get("ok", false)):
		_outcome_card.visible = true
		_set_card(
			"Pull failed: %s" % str(step.get("error", "?")),
			ThemeBuilder.DANGER,
			[] as Array[String]
		)
		return

	_history.append(step)
	_pending = step
	_outcome_card.visible = false
	_begin_reveal(step)


## Builds the beat queue — the resolver's events, with a PHASE beat spliced in
## wherever the fight moves on. A phase change is a moment, not another log line.
func _begin_reveal(step: Dictionary) -> void:
	var result: Dictionary = step["result"]
	_roster = result["participants"].size()
	_alive = _roster

	var phase_names := {}
	for phase: Dictionary in step.get("phases", []):
		phase_names[int(phase["phase_order"])] = str(phase.get("display_name", phase["slug"]))

	var events: Array = result["events"].duplicate()
	events.sort_custom(func(a, b): return int(a["sequence_no"]) < int(b["sequence_no"]))

	_queue = []
	(
		_queue
		. append(
			{
				"kind": "header",
				"text":
				"%s — attempt %d" % [str(step["encounter_name"]), int(step["attempt_number"])],
			}
		)
	)
	var phase := -1
	for event: Dictionary in events:
		var order := int(event["phase_order"])
		if order != phase:
			phase = order
			(
				_queue
				. append(
					{
						"kind": "phase",
						"order": order,
						"text": str(phase_names.get(order, "Phase %d" % order)),
					}
				)
			)
		_queue.append({"kind": "event", "event": event})
	_queue.append({"kind": "outcome"})

	for child in _feed.get_children():
		child.queue_free()
	_set_buttons_revealing(true)
	_refresh_status()

	if _instant:
		while not _queue.is_empty():
			_reveal_next()
		return
	_timer.wait_time = REVEAL_SECONDS / SPEEDS[_speed_index]
	_timer.start()
	_reveal_next()


func _reveal_next() -> void:
	if _queue.is_empty():
		_finish_reveal()
		return
	var beat: Dictionary = _queue.pop_front()
	match str(beat["kind"]):
		"header":
			_add_header(str(beat["text"]))
		"phase":
			_add_phase_beat(int(beat["order"]), str(beat["text"]))
		"event":
			_add_event(beat["event"])
		"outcome":
			_finish_reveal()
			return
	_scroll_to_bottom()


func _finish_reveal() -> void:
	_timer.stop()
	_queue.clear()
	if not _pending.is_empty():
		_render_outcome(_pending)
		_advance(_pending)
		_pending = {}
	_set_buttons_revealing(false)
	_refresh_status()
	_scroll_to_bottom()


## Rolling the pull forward: a kill moves to the next boss, a wipe raises the
## attempt number so the learning arc (and the player's patience) can build.
func _advance(step: Dictionary) -> void:
	if str(step["result"]["pull"]["outcome"]) == "kill":
		_boss_index += 1
		_attempt = 1
	else:
		_attempt += 1


func _is_revealing() -> bool:
	return not _queue.is_empty()


# --- the feed -----------------------------------------------------------------


func _add_header(text: String) -> void:
	var label := _rich()
	label.text = "[color=#%s][b]%s[/b][/color]" % [ThemeBuilder.ACCENT.to_html(false), text]
	_feed.add_child(label)


## A phase change reads as a beat: a ruled banner, not another grey line.
func _add_phase_beat(order: int, phase_name: String) -> void:
	var label := _rich()
	label.text = (
		"[color=#%s]────  PHASE %d · %s  ────[/color]"
		% [ThemeBuilder.ACCENT.to_html(false), order, phase_name.to_upper()]
	)
	_feed.add_child(label)
	_phase_label.text = "Phase %d — %s" % [order, phase_name]


func _add_event(event: Dictionary) -> void:
	var outcome := str(event["outcome"])
	var notability := PullContracts.notability_for(outcome)
	var text := str(event["log_line"])

	if (
		outcome
		in [
			Timeline.OUTCOME_DEATH,
			Timeline.OUTCOME_CASCADE_DEATH,
			Timeline.OUTCOME_TANK_DEATH,
			Timeline.OUTCOME_TANK_OVERWHELMED,
		]
	):
		_alive = maxi(0, _alive - 1)
		_refresh_alive()
	elif outcome == Timeline.OUTCOME_WIPE_CALL:
		# a wipe is a wipe: the raid does not walk out of it. Leaving the counter
		# at "20/20 up" under the word WIPE is the feed contradicting itself.
		_alive = 0
		_refresh_alive()

	# a kill is the one thing in this game that gets to be gold
	var tint := (
		ThemeBuilder.TRIUMPH
		if outcome == Timeline.OUTCOME_BOSS_DOWN
		else ThemeBuilder.notability_color(notability)
	)
	var colour := tint.to_html(false)

	var label := _rich()
	match notability:
		"decisive":
			label.text = ("[color=#%s][b]  ▶  %s[/b][/color]" % [colour, text])
			label.add_theme_font_size_override("normal_font_size", ThemeBuilder.FONT_SIZE + 3)
			label.add_theme_font_size_override("bold_font_size", ThemeBuilder.FONT_SIZE + 3)
		"critical":
			label.text = "[color=#%s][b]  •  %s[/b][/color]" % [colour, text]
		_:
			label.text = "[color=#%s]     %s[/color]" % [colour, text]
	_feed.add_child(label)


func _rich() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# --- the outcome card ---------------------------------------------------------


## The card answers the question the player actually has. On a kill: celebrate,
## unmistakably. On a wipe: name the cause, name what made it fatal, and — the
## thing that keeps a raider pulling — say whether this was the closest yet.
func _render_outcome(step: Dictionary) -> void:
	var pull: Dictionary = step["result"]["pull"]
	var slug := str(step["encounter_slug"])
	var outcome := str(pull["outcome"])
	var progress := 100 - int(pull["boss_hp_pct_at_end"])
	var previous_best := int(_best_pct.get(slug, 0))

	# the feed already closed with the fight's own gold "boss_down" beat — the card
	# is the aftermath, not a second victory lap
	var lines: Array[String] = []
	if outcome == "kill":
		lines.append(
			(
				"Down in %s with %d/%d raiders standing. Loot drops — open the report."
				% [_clock(int(pull["duration_sec"])), _alive, _roster]
			)
		)
		_set_card(
			(
				"★  KILL — %s falls on attempt %d"
				% [str(step["encounter_name"]), int(step["attempt_number"])]
			),
			ThemeBuilder.TRIUMPH,
			lines
		)
	else:
		# MI-005: the card speaks the DIAGNOSIS, never `wipe_reason` — that string
		# is internal shorthand full of margins and probabilities, and it names the
		# main tank in a way that reads like an accusation.
		var diagnosis: Dictionary = pull.get("diagnosis", {})
		lines.append(
			(
				"[b]Boss to %d%%[/b]  ·  %s  ·  %s"
				% [progress, _closeness(progress, previous_best), _clock(int(pull["duration_sec"]))]
			)
		)
		if diagnosis.is_empty():
			_set_card("WIPE — %s" % str(pull["wipe_reason"]), ThemeBuilder.DANGER, lines)
			return

		lines.append(str(diagnosis["headline"]))
		for factor: String in diagnosis.get("contributing_factors", []):
			lines.append("· %s" % factor)
		var key_moment: Dictionary = diagnosis.get("key_moment", {})
		if not key_moment.is_empty():
			lines.append("[b]Key moment[/b] — %s" % str(key_moment["log_line"]))
		lines.append(
			(
				"[color=#%s]→ %s[/color]"
				% [ThemeBuilder.ACCENT.to_html(false), str(diagnosis["recommendation"])]
			)
		)
		_set_card("WIPE — %s" % str(diagnosis["primary_cause_label"]), ThemeBuilder.DANGER, lines)

	_best_pct[slug] = maxi(previous_best, progress)


## The "one more pull" line. A wipe that got further than any before it is not a
## failure the player wants to walk away from — it is the reason they stay.
func _closeness(progress: int, previous_best: int) -> String:
	if previous_best <= 0:
		return "first attempt — that is your benchmark"
	if progress > previous_best:
		return (
			"[color=#%s][b]CLOSEST YET[/b][/color] (previous best %d%%)"
			% [ThemeBuilder.TRIUMPH.to_html(false), previous_best]
		)
	if progress == previous_best:
		return "matched your best"
	return "your best is still %d%%" % previous_best


func _clock(seconds: int) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), seconds % 60]


func _set_card(title: String, colour: Color, lines: Array[String]) -> void:
	for child in _outcome_card.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_outcome_card.add_child(box)

	var heading := _rich()
	heading.text = "[color=#%s][b]%s[/b][/color]" % [colour.to_html(false), title]
	heading.add_theme_font_size_override("bold_font_size", ThemeBuilder.FONT_SIZE + 4)
	box.add_child(heading)

	for line in lines:
		var label := _rich()
		label.text = "[color=#%s]%s[/color]" % [ThemeBuilder.TEXT.to_html(false), line]
		box.add_child(label)
	_outcome_card.visible = true


# --- status + controls --------------------------------------------------------


func _refresh_status() -> void:
	if _boss_index >= _bosses.size():
		_boss_label.text = "Night complete"
		_phase_label.text = ""
		_alive_label.text = "%d pulls" % _history.size()
		_best_label.text = ""
		_pull_button.disabled = true
		_next_button.disabled = true
		return

	var slug := _bosses[_boss_index]
	_boss_label.text = (
		"Boss %d/%d — %s  ·  attempt %d"
		% [
			_boss_index + 1,
			_bosses.size(),
			NightRunner.encounter_name(_campaign["db"], slug),
			_attempt,
		]
	)
	if not _is_revealing():
		_phase_label.text = ""
	_refresh_alive()
	var best := int(_best_pct.get(slug, 0))
	_best_label.text = "" if best <= 0 else "furthest yet: boss to %d%%" % best
	_pull_button.disabled = false
	_next_button.disabled = false


func _refresh_alive() -> void:
	_alive_label.text = "" if _roster == 0 else "raiders up: %d/%d" % [_alive, _roster]
	_alive_label.add_theme_color_override(
		"font_color", ThemeBuilder.DANGER if _alive < _roster else ThemeBuilder.TEXT
	)


func _set_buttons_revealing(revealing: bool) -> void:
	_pull_button.disabled = revealing
	_next_button.disabled = revealing
	_skip_button.disabled = not revealing


func _sync_pacing_buttons() -> void:
	_speed_button.text = "Speed %dx" % int(SPEEDS[_speed_index])
	_speed_button.disabled = _instant
	_instant_button.text = "Pacing: Instant" if _instant else "Pacing: Live"
	_skip_button.disabled = not _is_revealing()


func _on_cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	_timer.wait_time = REVEAL_SECONDS / SPEEDS[_speed_index]
	_sync_pacing_buttons()


func _on_toggle_instant() -> void:
	_instant = not _instant
	if _instant and _is_revealing():
		_on_skip_to_result()
	_sync_pacing_buttons()


## Drain the rest of the pull immediately — the player has seen enough.
func _on_skip_to_result() -> void:
	if not _is_revealing():
		return
	while not _queue.is_empty():
		var beat: Dictionary = _queue.front()
		if str(beat["kind"]) == "outcome":
			break
		_reveal_next()
	_finish_reveal()
	_sync_pacing_buttons()


func _on_skip_boss() -> void:
	if _is_revealing():
		return
	if _boss_index >= _bosses.size() - 1:
		_boss_index = _bosses.size()
	else:
		_boss_index += 1
		_attempt = 1
	_outcome_card.visible = false
	_refresh_status()


func _on_end_night() -> void:
	_timer.stop()
	if _shell.has_method("end_night"):
		_shell.end_night(_history)
