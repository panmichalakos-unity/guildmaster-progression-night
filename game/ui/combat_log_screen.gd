class_name CombatLogScreen
extends Control

## Combat-log tab (M4-003). Thin renderer over NightRunner — pull button
## resolves one attempt, feed shows resolver log_line rows verbatim.

var _campaign: Dictionary = {}
var _prep: Dictionary = {}
var _shell: Node
var _bosses: Array[String] = []
var _boss_index := 0
var _attempt := 1
var _history: Array[Dictionary] = []

var _header: Label
var _outcome: Label
var _feed: VBoxContainer
var _pull_button: Button
var _skip_button: Button
var _end_button: Button


func setup(campaign: Dictionary, prep: Dictionary, shell: Node) -> void:
	_campaign = campaign
	_prep = prep
	_shell = shell
	_bosses = NightRunner.encounter_slugs(campaign["db"], int(campaign["event_id"]))
	_build_layout()
	_refresh_header()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_header = Label.new()
	_header.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
	root.add_child(_header)

	_outcome = Label.new()
	_outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_outcome)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_feed)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	root.add_child(controls)
	_pull_button = Button.new()
	_pull_button.text = "Pull"
	_pull_button.pressed.connect(_on_pull)
	controls.add_child(_pull_button)
	_skip_button = Button.new()
	_skip_button.text = "Skip to next boss"
	_skip_button.pressed.connect(_on_skip_boss)
	controls.add_child(_skip_button)
	_end_button = Button.new()
	_end_button.text = "End night → Report"
	_end_button.pressed.connect(_on_end_night)
	controls.add_child(_end_button)


func _refresh_header() -> void:
	if _boss_index >= _bosses.size():
		_header.text = "Night complete — open the post-night report"
		_pull_button.disabled = true
		_skip_button.disabled = true
		_outcome.text = (
			"%d pull%s recorded." % [_history.size(), "s" if _history.size() != 1 else ""]
		)
		return
	var slug := _bosses[_boss_index]
	var name := NightRunner.encounter_name(_campaign["db"], slug)
	_header.text = (
		"Boss %d/%d — %s  ·  attempt %d" % [_boss_index + 1, _bosses.size(), name, _attempt]
	)
	_pull_button.disabled = false
	_skip_button.disabled = false


func _on_pull() -> void:
	if _boss_index >= _bosses.size():
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
		_outcome.text = "Pull failed: %s" % str(step.get("error", "?"))
		_outcome.add_theme_color_override("font_color", ThemeBuilder.DANGER)
		return
	_history.append(step)
	_render_step(step)
	var outcome := str(step["result"]["pull"]["outcome"])
	if outcome == "kill":
		_boss_index += 1
		_attempt = 1
		if _boss_index >= _bosses.size():
			_refresh_header()
			return
	else:
		_attempt += 1
	_refresh_header()


func _render_step(step: Dictionary) -> void:
	var pull: Dictionary = step["result"]["pull"]
	var outcome := str(pull["outcome"])
	var title := Label.new()
	title.text = (
		"── %s · attempt %d · %s ──"
		% [step["encounter_name"], step["attempt_number"], outcome.to_upper()]
	)
	title.add_theme_color_override(
		"font_color", ThemeBuilder.GOOD if outcome == "kill" else ThemeBuilder.DANGER
	)
	_feed.add_child(title)

	if outcome == "wipe":
		var wipe := Label.new()
		wipe.text = "Wipe: %s" % pull["wipe_reason"]
		wipe.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
		wipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_feed.add_child(wipe)
		_outcome.text = "WIPE — %s" % pull["wipe_reason"]
		_outcome.add_theme_color_override("font_color", ThemeBuilder.DANGER)
	else:
		_outcome.text = "KILL — loot drops available on the report"
		_outcome.add_theme_color_override("font_color", ThemeBuilder.GOOD)

	for event: Dictionary in step["result"]["events"]:
		var line := Label.new()
		line.text = str(event["log_line"])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_feed.add_child(line)


func _on_skip_boss() -> void:
	if _boss_index >= _bosses.size() - 1:
		_boss_index = _bosses.size()
	else:
		_boss_index += 1
		_attempt = 1
	_refresh_header()


func _on_end_night() -> void:
	if _shell.has_method("end_night"):
		_shell.end_night(_history)
