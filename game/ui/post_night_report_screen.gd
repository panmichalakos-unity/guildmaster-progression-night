class_name PostNightReportScreen
extends Control

## Post-night report tab (M4-004). Renders NightReport.build() — ratings,
## boss outcomes, wipe reasons, learning progress, and loot display stub.

var _report: Dictionary = {}


func setup(report: Dictionary) -> void:
	_report = report
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	root.add_child(_title("POST-NIGHT REPORT"))
	root.add_child(_body(str(_report.get("summary_line", ""))))

	root.add_child(_title("BOSSES"))
	for boss: Dictionary in _report.get("bosses", []):
		var status := "KILL" if bool(boss["killed"]) else "OPEN"
		var line := (
			"%s — %s (%d attempt%s)"
			% [
				boss["name"],
				status,
				int(boss["attempts"]),
				"s" if int(boss["attempts"]) != 1 else ""
			]
		)
		if not bool(boss["killed"]) and not str(boss["last_wipe_reason"]).is_empty():
			line += "\n  last wipe: %s" % boss["last_wipe_reason"]
		var label := _body(line)
		label.add_theme_color_override(
			"font_color", ThemeBuilder.GOOD if bool(boss["killed"]) else ThemeBuilder.DANGER
		)
		root.add_child(label)

	root.add_child(_title("LEARNING ARC"))
	var learning: Array = _report.get("learning", [])
	if learning.is_empty():
		root.add_child(_dim("No encounter progress recorded yet."))
	else:
		for row: Dictionary in learning:
			(
				root
				. add_child(
					_dim(
						(
							"%s — progress %d · %d attempt%s"
							% [
								row["name"],
								int(row["progress"]),
								int(row["attempt_count"]),
								"s" if int(row["attempt_count"]) != 1 else "",
							]
						)
					)
				)
			)

	var mvp: Dictionary = _report.get("mvp", {})
	if not mvp.is_empty():
		root.add_child(_title("MVP"))
		(
			root
			. add_child(
				_body(
					(
						"%s (%s) — avg rating %.1f across %d pull%s"
						% [
							mvp["handle"],
							mvp["role_slug"],
							float(mvp["avg_rating"]),
							int(mvp["pulls"]),
							"s" if int(mvp["pulls"]) != 1 else "",
						]
					)
				)
			)
		)

	root.add_child(_title("RATINGS"))
	for row: Dictionary in _report.get("ratings", []):
		(
			root
			. add_child(
				_dim(
					(
						"%-14s %-7s  %.1f  (%d death%s)"
						% [
							row["handle"],
							row["role_slug"],
							float(row["avg_rating"]),
							int(row["deaths"]),
							"s" if int(row["deaths"]) != 1 else "",
						]
					)
				)
			)
		)

	root.add_child(_title("WIPE REASONS"))
	var wipes: Array = _report.get("top_wipe_reasons", [])
	if wipes.is_empty():
		root.add_child(_dim("No wipes tonight."))
	else:
		for row: Dictionary in wipes:
			root.add_child(_dim("%dx  %s" % [int(row["count"]), row["reason"]]))

	root.add_child(_title("LOOT (display stub — claims land in M6)"))
	var loot: Array = _report.get("loot", [])
	if loot.is_empty():
		root.add_child(_dim("No kills with loot drops."))
	else:
		for item: Dictionary in loot:
			(
				root
				. add_child(
					_dim(
						(
							"%s — %s (ilvl %d, %s)%s"
							% [
								item["encounter_name"],
								item["display_name"],
								int(item["item_level"]),
								item["slot_slug"],
								(
									" [%s]" % item["spec_fit_tag"]
									if not str(item.get("spec_fit_tag", "")).is_empty()
									else ""
								),
							]
						)
					)
				)
			)


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim(text: String) -> Label:
	var label := _body(text)
	label.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	return label
