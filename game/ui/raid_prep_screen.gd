class_name RaidPrepScreen
extends Control

## Raid-prep screen (M4-002) — the first real tab. Thin renderer over the pure
## RaidPrep read model: lineup + bench (click to swap), live comp warnings on
## the three axes, auto-assignments, a consumable-plan picker, and "Lock in
## Lineup" which hands {lineup_ids, assignments, consumable_tier} to the shell
## for M4-003 to resolve. No sim math here — all of it is RaidPrep.build().

var _db: Variant
var _event_id: int
var _shell: Node
var _lineup_ids: Array[int] = []
var _consumable_tier := "basic"

var _lineup_box: VBoxContainer
var _bench_box: VBoxContainer
var _warnings_box: VBoxContainer
var _assign_box: VBoxContainer
var _coverage_label: Label
var _lock_button: Button


func setup(campaign: Dictionary, shell: Node) -> void:
	_db = campaign["db"]
	_event_id = int(campaign["event_id"])
	_shell = shell
	_lineup_ids = PullInputLoader.auto_lineup(_db)
	_build_layout()
	_refresh()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 560
	add_child(split)

	# left: lineup
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	left.add_child(_section_title("TONIGHT'S LINEUP"))
	_coverage_label = _dim_label("")
	left.add_child(_coverage_label)
	_lineup_box = _scroll_list(left)

	# right: bench + warnings + assignments + controls
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	split.add_child(right)

	right.add_child(_section_title("BENCH"))
	_bench_box = _scroll_list(right, 160)

	right.add_child(_section_title("COMP CHECK"))
	_warnings_box = VBoxContainer.new()
	right.add_child(_warnings_box)

	right.add_child(_section_title("ASSIGNMENTS"))
	_assign_box = VBoxContainer.new()
	right.add_child(_assign_box)

	var consumable_row := HBoxContainer.new()
	consumable_row.add_theme_constant_override("separation", 8)
	right.add_child(consumable_row)
	consumable_row.add_child(_dim_label("Consumable plan:"))
	var picker := OptionButton.new()
	picker.add_item("None", 0)
	picker.add_item("Basic", 1)
	picker.add_item("Premium", 2)
	picker.selected = 1
	picker.item_selected.connect(_on_consumable_selected)
	consumable_row.add_child(picker)

	_lock_button = Button.new()
	_lock_button.text = "Lock in Lineup  →  Combat Log"
	_lock_button.pressed.connect(_on_lock_pressed)
	right.add_child(_lock_button)


func _refresh() -> void:
	var report := RaidPrep.build(_db, _event_id, _lineup_ids)
	_lineup_ids = report["lineup_ids"]

	var coverage: Dictionary = report["coverage"]
	_coverage_label.text = (
		"%d / 20 raiders   —   %d tank · %d healer · %d melee · %d ranged"
		% [
			report["lineup"].size(),
			coverage["tank"],
			coverage["healer"],
			coverage["melee"],
			coverage["ranged"],
		]
	)

	_fill_roster(_lineup_box, report["lineup"], "Bench")
	_fill_roster(_bench_box, report["bench"], "Add")

	_clear(_warnings_box)
	for warning: Dictionary in report["warnings"]:
		var label := Label.new()
		var mark := "✓" if str(warning["severity"]) == "ok" else "⚠"
		label.text = "%s  %s" % [mark, warning["text"]]
		label.add_theme_color_override(
			"font_color",
			ThemeBuilder.GOOD if str(warning["severity"]) == "ok" else ThemeBuilder.ACCENT
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# MI-008 — progressive disclosure. The warning already says the consequence
		# and the fix in plain language; the tooltip is the DEPTH a veteran (or a
		# curious newcomer) can reach for. It is never required to act.
		var term := str(warning.get("term", ""))
		if not term.is_empty() and Glossary.has_term(term):
			var entry := Glossary.entry(term)
			label.tooltip_text = "%s — %s\n\n%s" % [entry["term"], entry["plain"], entry["detail"]]
			label.mouse_filter = Control.MOUSE_FILTER_STOP
		_warnings_box.add_child(label)

	_clear(_assign_box)
	for line: String in report["assignment_summary"]:
		_assign_box.add_child(_dim_label(line))

	_lock_button.disabled = not bool(report["ready"])


func _fill_roster(box: VBoxContainer, rows: Array, action: String) -> void:
	_clear(box)
	for row: Dictionary in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var caps := ""
		if int(row["uncrittable"]) == 1:
			caps = " [UC]"
		elif int(row["hit_capped"]) == 1:
			caps = " [HC]"
		var info := Label.new()
		info.text = (
			"%-13s %-7s %-11s GS%d%s"
			% [row["handle"], row["role_slug"], row["spec_name"], int(row["gear_score"]), caps]
		)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		var button := Button.new()
		button.text = action
		var avatar_id := int(row["avatar_id"])
		button.pressed.connect(func() -> void: _on_swap(avatar_id))
		line.add_child(button)
		box.add_child(line)


# --- interaction --------------------------------------------------------------


func _on_swap(avatar_id: int) -> void:
	_lineup_ids = RaidPrep.toggle(_lineup_ids, avatar_id)
	_refresh()


func _on_consumable_selected(index: int) -> void:
	_consumable_tier = ["", "basic", "premium"][index]


func _on_lock_pressed() -> void:
	var report := RaidPrep.build(_db, _event_id, _lineup_ids)
	if _shell.has_method("lock_prep"):
		(
			_shell
			. lock_prep(
				{
					"lineup_ids": _lineup_ids,
					"assignments": report["assignments"],
					"consumable_tier": _consumable_tier,
				}
			)
		)


# --- little builders ----------------------------------------------------------


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
	return label


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	return label


func _scroll_list(parent: VBoxContainer, min_height: int = 0) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if min_height > 0:
		scroll.custom_minimum_size = Vector2(0, min_height)
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _clear(box: VBoxContainer) -> void:
	for child in box.get_children():
		child.queue_free()
		box.remove_child(child)
