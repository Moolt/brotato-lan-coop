extends Node

const MOD_DIR: = "Moolt-Lan_Coop"
const LOG_NAME: = "Moolt-Lan_Coop"

var mod_dir_path: = ""
var ext_dir: = ""
# The installed EARLY_EXTENSIONS: the resource cache doesn't hold them, without a reference they
# are freed and the vanilla script is back at its path.
var _early_extensions: = []

# Installed here with take_over_path, before ModLoader compiles anything, instead of through
# ModLoader. In the shipped game vanilla scripts are compiled .gdc files without source:
# - Vanilla classes with class_name subclasses (Weapon: MeleeWeapon, RangedWeapon; Item:
#   Consumable, Gold; ...). After installing an extension ModLoader calls reload() on the base's
#   subclasses so they re-resolve their base, and on a .gdc that turns each into an empty script
#   (Consumable no longer extends Item, main.gdc fails to load, the game doesn't start). Installed
#   first, a subclass loaded later finds the extension at its base's path.
# - Classes in vanilla function signatures that a script or its subclass overrides
#   (on_entity_birth_timeout(EntityBirth), _on_shop_item_focused(ShopItem, int)): a .gdc compiled
#   before the extension is installed holds the vanilla class there, and an override compiled
#   after it doesn't match ("The function signature doesn't match the parent").
# The decompiled sources (the test copy) need none of this; they reload fine.
const EARLY_EXTENSIONS: = [
	"entities/birth/entity_birth.gd",
	"ui/menus/shop/shop_item.gd",
	"items/global/item.gd",
	"projectiles/projectile.gd",
	"weapons/weapon.gd",
	"entities/units/enemies/enemy.gd",
	"entities/structures/turret/turret.gd",
	"entities/units/player/player.gd",
]
# Installed the same way, but in _ready: since 1.2.0.1 base_shop.gd infers types from the
# RunData autoload (var next_wave: = RunData.get_next_wave()), and an autoload's name only has a
# type once every autoload is instanced, after ModLoader's _init (where mods run _init).
# Nothing loads the shop scripts before then.
const READY_EXTENSIONS: = [
	"ui/menus/shop/base_shop.gd",
]


func _init() -> void :
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)
	ext_dir = mod_dir_path.plus_file("extensions")
	for path in EARLY_EXTENSIONS:
		_install_early_extension(ext_dir.plus_file(path))
	# One line per vanilla script to extend (path mirrors the vanilla path):
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/progress_data.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/title_screen/title_screen_menus.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/ingame/ingame_main_menu.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/ingame/pause_menu.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/global/popup_manager.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("main.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/movement_behaviors/player_movement_behavior.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/enemies/attack_behaviors/shooting_attack_behavior.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("overlap/hurtbox.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("particles/burning/burning_particles.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/weapon_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/focus_emulator_signal.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("global/entity_spawner.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("global/gpe_spawner.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("global/stats_manager.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/coop_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/debug_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/run_data.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/challenge_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("entities/units/pet/jellyshield/jellyshield.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/utils.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/zone_service.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("singletons/progress_data_loader_v3.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/run/base_end_run.gd"))
	ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/run/end_run.gd"))


func _install_early_extension(extension_path: String) -> void :
	var extension: Script = load(extension_path)
	var base_path: String = extension.get_base_script().resource_path
	extension.take_over_path(base_path)
	_early_extensions.append(extension)
	ModLoaderLog.info("Installed early extension: %s <- %s" % [base_path, extension_path], LOG_NAME)


func _ready() -> void :
	for path in READY_EXTENSIONS:
		_install_early_extension(ext_dir.plus_file(path))
	load(mod_dir_path.plus_file("net/net_translations.gd")).register()
	load(mod_dir_path.plus_file("modes/mode_registry.gd")).register_translations()

	# The root is busy setting up autoloads at this point, so add LanNet deferred.
	var net_manager: Node = load(mod_dir_path.plus_file("net/net_manager.gd")).new()
	net_manager.name = "LanNet"
	get_tree().root.call_deferred("add_child", net_manager)

	ModLoaderLog.info("LanCoop loaded", LOG_NAME)
