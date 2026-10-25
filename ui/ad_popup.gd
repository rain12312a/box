class_name AdPopup
extends Control
## Placeholder rewarded ad: a 5 second countdown that the player cannot skip.
## The caller decides what the reward or the unlocked action is.

signal completed

var _seconds := ItemCatalog.AD_SECONDS
var _remaining := 0.0
var _finished := false
var _on_complete: Callable = Callable()
var _count_label: Label
var _progress: ProgressBar
var _claim: Button


static func open(parent: Node, on_complete: Callable, seconds := ItemCatalog.AD_SECONDS) -> AdPopup:
	if parent == null or not is_instance_valid(parent):
		return null
	var popup := AdPopup.new()
	popup._on_complete = on_complete
	popup._seconds = maxf(seconds, 0.1)
	parent.add_child(popup)
	return popup


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Board sprites use absolute z indices (3..30), so the modal has to sit above them.
	z_index = 250
	_remaining = _seconds
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.035, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UIKit.panel(0, "CardPanel")
	card.custom_minimum_size = Vector2(660, 0)
	center.add_child(card)
	var v := UIKit.vbox(0)
	card.add_child(v)

	var banner_wrap := Control.new()
	banner_wrap.custom_minimum_size = Vector2(660, 226)
	banner_wrap.clip_contents = true
	banner_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(banner_wrap)
	var banner := TextureRect.new()
	banner.texture = UIKit.art("ad_banner")
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_wrap.add_child(banner)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 30)
	body_margin.add_theme_constant_override("margin_right", 30)
	body_margin.add_theme_constant_override("margin_top", 18)
	body_margin.add_theme_constant_override("margin_bottom", 24)
	v.add_child(body_margin)
	var body := UIKit.vbox(10)
	body_margin.add_child(body)

	var title := UIKit.heading(Loc.t("ad_title"), 28, UIKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var subtitle := UIKit.label(Loc.t("ad_subtitle"), 14, UIKit.COL_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(subtitle)

	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UIKit.COL_BG_2
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.COL_GOLD
	fill.set_corner_radius_all(5)
	_progress.add_theme_stylebox_override("background", bg)
	_progress.add_theme_stylebox_override("fill", fill)
	body.add_child(_progress)

	_count_label = UIKit.label("", 17, UIKit.COL_TEXT, true)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_count_label)

	_claim = UIKit.button("", "check", "PrimaryButton", 50)
	_claim.disabled = true
	_claim.pressed.connect(_claim_reward)
	body.add_child(_claim)
	_refresh()
	set_process(true)


func _process(delta: float) -> void:
	if _finished:
		return
	_remaining = maxf(_remaining - delta, 0.0)
	_refresh()
	if _remaining <= 0.0:
		set_process(false)


func _refresh() -> void:
	var ratio := 1.0 - _remaining / _seconds
	_progress.value = clampf(ratio, 0.0, 1.0) * 100.0
	if _remaining > 0.0:
		_count_label.text = Loc.t("ad_countdown", [int(ceil(_remaining))])
		_claim.text = Loc.t("ad_wait", [int(ceil(_remaining))])
		_claim.disabled = true
	else:
		_count_label.text = Loc.t("ad_ready")
		_claim.text = Loc.t("ad_claim")
		_claim.disabled = false


## Used by the automated tests to skip the countdown.
func finish_now() -> void:
	if _finished:
		return
	_remaining = 0.0
	_refresh()
	_claim_reward()


func is_finished() -> bool:
	return _finished


func _claim_reward() -> void:
	if _finished or _remaining > 0.0:
		return
	_finished = true
	Audio.play_sfx("goal", -6.0, 0.0)
	var done := _on_complete
	_on_complete = Callable()
	queue_free()
	if done.is_valid():
		done.call()
	completed.emit()
