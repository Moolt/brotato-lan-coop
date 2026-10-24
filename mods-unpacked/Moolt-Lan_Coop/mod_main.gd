extends Node

const MOD_DIR: = "Moolt-Lan_Coop"
const LOG_NAME: = "Moolt-Lan_Coop"

var mod_dir_path: = ""
var ext_dir: = ""


func _init() -> void :
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)
	ext_dir = mod_dir_path.plus_file("extensions")
	# One line per vanilla script to extend (path mirrors the vanilla path):
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/progress_data.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/title_screen/title_screen_menus.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/ingame/ingame_main_menu.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/ingame/pause_menu.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/global/popup_manager.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("main.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/movement_behaviors/player_movement_behavior.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/player/player.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/birth/entity_birth.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("weapons/weapon.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("projectiles/projectile.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/enemies/enemy.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/structures/turret/turret.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("overlap/hurtbox.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("particles/burning/burning_particles.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/weapon_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("items/global/item.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/focus_emulator_signal.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("global/entity_spawner.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("global/stats_manager.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/coop_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/debug_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/run_data.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/challenge_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/pet/jellyshield/jellyshield.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/utils.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/zone_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/shop/base_shop.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/shop/shop_item.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/progress_data_loader_v3.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/run/base_end_run.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/run/end_run.gd"))


func _ready() -> void :
	load(mod_dir_path.plus_file("net/net_translations.gd")).register()
	load(mod_dir_path.plus_file("modes/mode_registry.gd")).register_translations()

	# The root is busy setting up autoloads at this point, so add LanNet deferred.
	var net_manager: Node = load(mod_dir_path.plus_file("net/net_manager.gd")).new()
	net_manager.name = "LanNet"
	get_tree().root.call_deferred("add_child", net_manager)

	ModLoaderLog.info("LanCoop loaded", LOG_NAME)
