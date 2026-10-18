extends "res://ui/menus/shop/base_shop.gd"

# Between waves of a LAN session every machine shows the solo shop for its own player (RunData
# is the solo view, game/solo_view.gd). Go doesn't start the next wave here: it sends the own
# solo run to the host (LanNet.send_shop_done) and shows who is still shopping over the shop.
# "Back to the shop" (or cancel) takes the Go back. The host goes on once everyone is done.
# Vanilla's once-per-wave Go parts (hourglass, elite rolls, the wave increment) run on the host.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const ShopWaitingOverlay = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/shop_waiting_overlay.gd")

var _lan_overlay: Control = null


# Runs after vanilla's _ready.
func _ready() -> void :
	if not LanGame.in_session():
		return
	_lan_overlay = ShopWaitingOverlay.new()
	# Above the shop content; the pause menu hides the content and the overlay (on_paused).
	add_child_below_node($Content, _lan_overlay)
	var _e = _lan_overlay.connect("back_pressed", self, "_lan_on_back_pressed")
	_e = LanGame.get_lan_net().connect("shop_waiting_changed", self, "_lan_on_shop_waiting_changed")
	# shop.gd's _ready (after this one) shows the Endless button before wave 20. Endless is
	# run-wide but each machine would set it alone, so it stays off in a session.
	call_deferred("_lan_hide_endless_button")


func _lan_hide_endless_button() -> void :
	var endless_button = get_node_or_null("%EndlessButton")
	if endless_button != null and endless_button.visible:
		endless_button.hide()
		# shop.gd pointed the Go button's focus up at it.
		_get_go_button(0).focus_neighbour_top = NodePath()


func _on_GoButton_pressed(player_index: int) -> void :
	if _lan_overlay == null:
		._on_GoButton_pressed(player_index)
		return
	if get_tree().paused or _player_pressed_go_button[player_index]:
		return
	_player_pressed_go_button[player_index] = true
	_lan_mark_item_locking(player_index)
	var lan_net = LanGame.get_lan_net()
	var names: Array = lan_net.shop_waiting_names.duplicate()
	var own_entry = lan_net.get_local_player()
	if own_entry != null:
		names.erase(own_entry.name)
	_lan_overlay.open(names)
	# The last Go makes the host go on right away, so this comes after opening the overlay.
	lan_net.send_shop_done(true)


# Vanilla takes the Go back when the Go button loses focus; in a session the overlay takes the
# focus right after Go, and only its button (or cancel) takes the Go back.
func _on_GoButton_focus_exited(player_index: int) -> void :
	if _lan_overlay == null:
		._on_GoButton_focus_exited(player_index)


# Vanilla calls this for Go pressed again and for cancel while Go is pressed.
func _clear_go_button_pressed(player_index: int) -> void :
	._clear_go_button_pressed(player_index)
	if _lan_overlay != null and _lan_overlay.visible:
		_lan_overlay.hide()
		LanGame.get_lan_net().send_shop_done(false)
		Utils.focus_player_control(_get_go_button(player_index), player_index)


# Vanilla curses locked items when the shop closes. In a session the host does that for every
# player while merging (RunBuilder.apply_go); here RunData is already the merged run.
func _on_tree_exited() -> void :
	if not LanGame.in_session():
		._on_tree_exited()


func on_paused() -> void :
	.on_paused()
	if _lan_overlay != null:
		_lan_overlay.hide()


func on_unpaused() -> void :
	.on_unpaused()
	if _lan_overlay != null and _player_pressed_go_button[0]:
		_lan_overlay.show()
		_lan_overlay.focus()


# Vanilla's Go: a locked shop item counts for the candy bag challenge. Only this machine sees
# its shop items, so this runs here instead of on the host.
func _lan_mark_item_locking(player_index: int) -> void :
	if not RunData.get_player_effects(player_index).has(Keys.used_item_locking_hash):
		return
	if ChallengeService.is_challenge_completed(ChallengeService.chal_candy_bag_hash) or RunData.get_player_effect_bool(Keys.used_item_locking_hash, player_index):
		return
	for shop_item in _get_shop_items_container(player_index)._shop_items:
		if shop_item != null and shop_item.active and shop_item.locked:
			RunData.get_player_effects(player_index)[Keys.used_item_locking_hash] = 1


func _lan_on_back_pressed() -> void :
	_clear_go_button_pressed(0)


func _lan_on_shop_waiting_changed() -> void :
	_lan_overlay.set_names(LanGame.get_lan_net().shop_waiting_names)
