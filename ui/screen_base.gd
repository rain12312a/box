class_name ScreenBase
extends Control
## Base class for full-screen views. Subclasses build their UI in _build().

var params: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_after_build()


func _build() -> void:
	pass


func _after_build() -> void:
	pass


func t(key: String, args: Array = []) -> String:
	return Loc.t(key, args)


func add_background(variant := "menu") -> Background:
	var bg := Background.new()
	bg.variant = variant
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(bg, 0)
	return bg


func toast(text: String, duration := 2.0) -> void:
	UIKit.toast(self, text, duration)


func confirm(title: String, body: String, confirm_text: String, on_confirm: Callable,
		danger := false) -> void:
	UIKit.confirm(self, title, body, confirm_text, on_confirm, Callable(), danger)
