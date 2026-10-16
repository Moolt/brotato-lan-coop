extends Node

const MOD_DIR: = "Moolt-Lan_Coop"
const LOG_NAME: = "Moolt-Lan_Coop"

var mod_dir_path: = ""
var ext_dir: = ""


func _init() -> void :
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)
	ext_dir = mod_dir_path.plus_file("extensions")
	# One line per vanilla script to extend (path mirrors the vanilla path):
	# ModLoaderMod.install_script_extension(ext_dir.plus_file("ui/menus/title_screen/title_screen_menus.gd"))


func _ready() -> void :
	ModLoaderLog.info("LanCoop loaded", LOG_NAME)
	# Later: add the network manager to the root (deferred, root is busy during autoload setup)
	# get_tree().root.call_deferred("add_child", load(mod_dir_path.plus_file("net/net_manager.gd")).new())
