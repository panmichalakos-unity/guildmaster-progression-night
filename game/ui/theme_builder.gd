class_name ThemeBuilder
extends RefCounted

## THE slice theme (M4-001) — built in code, zero binary assets (stack doc:
## no art spend before the fun gate; the loop must earn the verdict naked).
## Dark FM-style data-panel look with an Emberdeep accent. Swapping palette
## constants here re-skins every screen at once.

const BG := Color("14161a")  # window background
const PANEL := Color("1e2229")  # panels / tab body
const PANEL_EDGE := Color("2c313a")
const TEXT := Color("d8d5cd")
const TEXT_DIM := Color("8b8f98")
const ACCENT := Color("d97a32")  # ember
const DANGER := Color("c0392b")
const GOOD := Color("27ae60")

## MI-004 — the notability palette. The combat log's job is to make the moment the
## pull TURNED legible at a glance, so the four tiers must be separable in
## peripheral vision: routine recedes, decisive shouts. See
## docs/guildmaster-presentation.md and PullContracts.notability_for().
const ROUTINE := Color("6e727a")  # texture; the fight breathing
const NOTABLE := Color("d8d5cd")  # worth reading
const CRITICAL := Color("e08a4a")  # somebody died / a duty dropped
const DECISIVE := Color("ff5544")  # the pull turned HERE
const TRIUMPH := Color("e8c266")  # gold — reserved for a kill, nothing else

const FONT_SIZE := 15
const FONT_SIZE_TITLE := 28


## BBCode colour for a notability tier (PullContracts.notability_for()).
static func notability_color(notability: String) -> Color:
	match notability:
		"decisive":
			return DECISIVE
		"critical":
			return CRITICAL
		"notable":
			return NOTABLE
		_:
			return ROUTINE


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = PANEL_EDGE
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(12)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	var button := StyleBoxFlat.new()
	button.bg_color = PANEL_EDGE
	button.set_corner_radius_all(4)
	button.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", button)
	var button_hover: StyleBoxFlat = button.duplicate()
	button_hover.bg_color = ACCENT.darkened(0.35)
	theme.set_stylebox("hover", "Button", button_hover)
	var button_pressed: StyleBoxFlat = button.duplicate()
	button_pressed.bg_color = ACCENT.darkened(0.15)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)

	var tab_panel: StyleBoxFlat = panel.duplicate()
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)

	var field := StyleBoxFlat.new()
	field.bg_color = BG
	field.border_color = PANEL_EDGE
	field.set_border_width_all(1)
	field.set_corner_radius_all(3)
	field.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)

	return theme
