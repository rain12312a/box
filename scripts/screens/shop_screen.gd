extends ScreenBase
## Coin shop: buy consumable items and watch a rewarded ad for extra coins.

var _coins_label: Label
var _ad_button: Button
var _buy_buttons: Dictionary = {}
var _owned_labels: Dictionary = {}


func _build() -> void:
	add_background("editor")
	Audio.play_music("music_menu")
	if not SaveManager.wallet_changed.is_connected(_refresh):
		SaveManager.wallet_changed.connect(_refresh)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var root := UIKit.vbox(14)
	margin.add_child(root)

	var header := UIKit.hbox(12)
	root.add_child(header)
	var back := UIKit.button(t("common_back"), "arrow_left", "GhostButton", 42)
	back.pressed.connect(func(): Game.goto("menu"))
	header.add_child(back)
	var title_box := UIKit.vbox(0)
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_box)
	title_box.add_child(UIKit.label(t("shop_kicker"), 11, UIKit.COL_TEAL, true))
	title_box.add_child(UIKit.heading(t("shop_title"), 26, UIKit.COL_TEXT))
	header.add_child(UIKit.expand_spacer())

	var wallet := UIKit.panel(12, "FlatPanel")
	wallet.custom_minimum_size = Vector2(150, 54)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wallet_row := UIKit.hbox(8)
	wallet.add_child(wallet_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = UIKit.icon("coin")
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = UIKit.COL_GOLD
	wallet_row.add_child(coin_icon)
	var wallet_box := UIKit.vbox(0)
	wallet_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet_row.add_child(wallet_box)
	wallet_box.add_child(UIKit.label(t("shop_wallet"), 11, UIKit.COL_MUTED))
	_coins_label = UIKit.label("0", 20, UIKit.COL_GOLD, true)
	wallet_box.add_child(_coins_label)
	header.add_child(wallet)

	var subtitle := UIKit.label(t("shop_subtitle"), 13, UIKit.COL_MUTED)
	root.add_child(subtitle)
	root.add_child(UIKit.divider())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for item_id in ItemCatalog.ORDER:
		grid.add_child(_build_card(item_id))

	var footer := UIKit.hbox(12)
	root.add_child(footer)
	var ad_card := UIKit.panel(16, "FlatPanel")
	ad_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(ad_card)
	var ad_row := UIKit.hbox(14)
	ad_card.add_child(ad_row)
	var ad_icon := TextureRect.new()
	ad_icon.texture = UIKit.icon("ad")
	ad_icon.custom_minimum_size = Vector2(38, 38)
	ad_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ad_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ad_icon.modulate = UIKit.COL_GOLD
	ad_row.add_child(ad_icon)
	var ad_text := UIKit.vbox(2)
	ad_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ad_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ad_row.add_child(ad_text)
	ad_text.add_child(UIKit.label(t("shop_ad_title"), 15, UIKit.COL_TEXT, true))
	ad_text.add_child(UIKit.label(t("shop_ad_body", [int(ItemCatalog.AD_SECONDS),
			ItemCatalog.AD_REWARD]), 12, UIKit.COL_MUTED))
	_ad_button = UIKit.button(t("shop_ad_button", [ItemCatalog.AD_REWARD]), "play", "PrimaryButton", 46)
	_ad_button.custom_minimum_size = Vector2(200, 46)
	_ad_button.pressed.connect(_watch_ad)
	ad_row.add_child(_ad_button)

	_refresh()
	back.grab_focus()


func _build_card(item_id: String) -> Control:
	var card := UIKit.panel(16, "CardPanel")
	card.custom_minimum_size = Vector2(388, 176)
	var v := UIKit.vbox(8)
	card.add_child(v)
	var top := UIKit.hbox(12)
	v.add_child(top)
	var icon := TextureRect.new()
	icon.texture = UIKit.icon(ItemCatalog.icon_name(item_id))
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UIKit.COL_GOLD
	top.add_child(icon)
	var name_box := UIKit.vbox(0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name_box)
	name_box.add_child(UIKit.label(ItemCatalog.display_name(item_id), 17, UIKit.COL_TEXT, true))
	var owned := UIKit.label("", 12, UIKit.COL_MUTED)
	name_box.add_child(owned)
	_owned_labels[item_id] = owned
	var price_row := UIKit.hbox(4)
	price_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(price_row)
	var coin := TextureRect.new()
	coin.texture = UIKit.icon("coin")
	coin.custom_minimum_size = Vector2(18, 18)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.modulate = UIKit.COL_GOLD
	price_row.add_child(coin)
	price_row.add_child(UIKit.label(str(ItemCatalog.price(item_id)), 17, UIKit.COL_GOLD, true))

	var desc := UIKit.label(ItemCatalog.description(item_id), 12, UIKit.COL_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)

	var buy := UIKit.button(t("shop_buy"), "plus", "PrimaryButton", 40)
	buy.pressed.connect(func(): _buy(item_id))
	v.add_child(buy)
	_buy_buttons[item_id] = buy
	return card


func _buy(item_id: String) -> void:
	if SaveManager.buy_item(item_id):
		Audio.play_sfx("goal", -8.0, 0.0)
		toast(t("item_bought", [ItemCatalog.display_name(item_id)]), 1.8)
	else:
		Audio.play_sfx("error", -10.0)
		toast(t("shop_need_coins", [ItemCatalog.price(item_id)]), 2.2)


func _watch_ad() -> void:
	if _ad_button.disabled:
		return
	_ad_button.disabled = true
	var popup := AdPopup.open(self, func():
		SaveManager.add_coins(ItemCatalog.AD_REWARD)
		Audio.play_sfx("goal", -4.0, 0.0)
		toast(t("shop_ad_reward", [ItemCatalog.AD_REWARD]), 2.4)
		if is_instance_valid(_ad_button):
			_ad_button.disabled = false
	)
	if popup == null and is_instance_valid(_ad_button):
		_ad_button.disabled = false


func _refresh() -> void:
	if _coins_label == null:
		return
	_coins_label.text = str(SaveManager.wallet_coins())
	for item_id in _buy_buttons.keys():
		var b: Button = _buy_buttons[item_id]
		var affordable := SaveManager.wallet_coins() >= ItemCatalog.price(item_id)
		b.disabled = not affordable
		var owned: Label = _owned_labels.get(item_id)
		if owned != null:
			owned.text = t("shop_owned", [SaveManager.item_count(item_id)])
