extends Control

## Vertical-slice app shell (M4-001). The WHOLE UI tree is built in code —
## no editor-authored layouts to drift; the .tscn is just this root.
##
## Shared data flow contract for M4-002/003/004: this node owns `campaign`
## (the DemoCampaign dictionary) and the TabContainer. Screen tasks REPLACE
## their placeholder tab with a real panel that reads `campaign` and the sim
## read models (RosterReport / PullInputLoader / PullResolver) — never a
## parallel shell, never direct sim math in UI.

var campaign: Dictionary = {}
## The locked raid-prep result (lineup_ids + assignments + consumable_tier)
## from M4-002, consumed by the combat-log tab (M4-003).
var prep_result: Dictionary = {}
## Pull history from the combat-log tab, consumed by the report (M4-004).
var night_pulls: Array = []

var _menu: CenterContainer
var _game: VBoxContainer
var _tabs: TabContainer
var _seed_edit: LineEdit
var _status: Label
var _guild_label: Label
var _night_label: Label


func _ready() -> void:
	theme = ThemeBuilder.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = ThemeBuilder.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_build_menu()
	_build_game_panel()
	_show_menu()


# --- menu ----------------------------------------------------------------------


func _build_menu() -> void:
	_menu = CenterContainer.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "GUILDMASTER: PROGRESSION NIGHT"
	title.add_theme_font_size_override("font_size", ThemeBuilder.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Phase A vertical slice — one raid night in The Emberdeep"
	subtitle.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	box.add_child(subtitle)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	box.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Night seed:"
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	# time-derived default (NOT the banned scattered randi(); CLAUDE.md rule 7).
	# The night is fully reproducible from whatever number ends up in this box.
	_seed_edit.text = str(int(Time.get_unix_time_from_system()) % 1000000)
	_seed_edit.custom_minimum_size = Vector2(160, 0)
	seed_row.add_child(_seed_edit)

	var start := Button.new()
	start.text = "Assemble the Raid"
	start.pressed.connect(_on_start_pressed)
	box.add_child(start)

	_status = Label.new()
	_status.text = ""
	_status.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	box.add_child(_status)


func _on_start_pressed() -> void:
	var seed_value := int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 133742
	_status.text = "Generating %s (seed %d)..." % [DemoCampaign.DEMO_GUILD_NAME, seed_value]
	await get_tree().process_frame  # let the status paint before the build
	campaign = DemoCampaign.build(seed_value)
	if campaign.is_empty():
		_status.text = "Campaign build failed — see logs."
		return
	_show_game()


# --- game panel ------------------------------------------------------------------


func _build_game_panel() -> void:
	_game = VBoxContainer.new()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game.add_theme_constant_override("separation", 8)
	add_child(_game)

	var top_bar := PanelContainer.new()
	_game.add_child(top_bar)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	top_bar.add_child(bar)
	_guild_label = Label.new()
	_guild_label.add_theme_color_override("font_color", ThemeBuilder.ACCENT)
	bar.add_child(_guild_label)
	_night_label = Label.new()
	_night_label.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	bar.add_child(_night_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game.add_child(_tabs)


func _show_menu() -> void:
	_menu.visible = true
	_game.visible = false


func _show_game() -> void:
	_menu.visible = false
	_game.visible = true
	_guild_label.text = str(campaign["guild_name"])
	_night_label.text = "The Emberdeep — night seed %d" % int(campaign["seed"])
	_clear_tabs()
	_mount_raid_prep()
	_tabs.current_tab = 0


func _clear_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()


## Injects the real M4-002 prep screen as tab 0.
func _mount_raid_prep() -> void:
	var prep := RaidPrepScreen.new()
	prep.name = "Raid Prep"
	_tabs.add_child(prep)
	prep.setup(campaign, self)
	# placeholders until lock / end-night mount the real screens
	_add_placeholder_tab("Combat Log", "Lock in a lineup to open the combat log.")
	_add_placeholder_tab(
		"Post-Night Report", "End the night from the combat log to open the report."
	)


func _add_placeholder_tab(tab_title: String, note: String) -> void:
	var panel := PanelContainer.new()
	panel.name = tab_title
	var label := Label.new()
	label.text = note
	label.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_tabs.add_child(panel)


## Called by the prep screen when the player locks the lineup (M4-002 -> M4-003).
func lock_prep(result: Dictionary) -> void:
	prep_result = result
	night_pulls = []
	_replace_tab(1, _make_combat_log())
	_tabs.current_tab = 1


func _make_combat_log() -> Control:
	var screen := CombatLogScreen.new()
	screen.name = "Combat Log"
	screen.setup(campaign, prep_result, self)
	return screen


## Called by the combat-log screen when the night ends (M4-003 -> M4-004).
func end_night(pulls: Array) -> void:
	night_pulls = pulls
	var report := NightReport.build(campaign["db"], pulls, int(campaign["guild_id"]))
	_replace_tab(2, _make_report(report))
	_tabs.current_tab = 2


func _make_report(report: Dictionary) -> Control:
	var screen := PostNightReportScreen.new()
	screen.name = "Post-Night Report"
	screen.setup(report)
	return screen


func _replace_tab(index: int, screen: Control) -> void:
	while _tabs.get_child_count() <= index:
		_add_placeholder_tab("Tab", "")
	var old: Node = _tabs.get_child(index)
	_tabs.remove_child(old)
	old.queue_free()
	_tabs.add_child(screen)
	_tabs.move_child(screen, index)


func _exit_tree() -> void:
	if not campaign.is_empty() and campaign.has("db"):
		campaign["db"].close_db()
