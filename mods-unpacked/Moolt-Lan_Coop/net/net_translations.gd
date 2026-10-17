extends Reference

# Runtime translations for the mod's own keys. Registered once by mod_main.

const STRINGS: = {
	"en": {
		"MENU_MULTIPLAYER": "Multiplayer", 
		"LAN_REJECT_VERSION": "The host runs a different version of the LAN Coop mod.", 
		"LAN_REJECT_GAME_VERSION": "The host runs a different version of Brotato.", 
		"LAN_REJECT_DLC": "The host has a different set of DLCs enabled.", 
		"LAN_REJECT_FULL": "The lobby is full.", 
		"LAN_REJECT_IN_PROGRESS": "A run is already in progress.", 
		"LAN_REJECT_BAD_HELLO": "The host could not read the join request.", 
		"LAN_MSG_HOST_LEFT": "The host closed the session.", 
		"LAN_MSG_CONNECTION_FAILED": "Could not connect to the host.", 
		"LAN_MSG_SERVER_FAILED": "Could not start the server. Is the port already in use?", 
		"LAN_MSG_INVALID_IP": "Please enter a valid IP address.", 
		"LAN_MSG_INVALID_PORT": "Please enter a port between 1 and 65535.", 
		"LAN_MULTIPLAYER_TITLE": "LAN Multiplayer", 
		"LAN_NAME": "Name", 
		"LAN_HOST_IP": "Host IP", 
		"LAN_PORT": "Port", 
		"LAN_HOST": "Host", 
		"LAN_JOIN": "Join", 
		"LAN_CONNECTING": "Connecting to {0}...", 
		"LAN_LOBBY": "Lobby", 
		"LAN_LEAVE": "Leave", 
		"LAN_JOIN_ADDRESS": "Others join with: {0} (port {1})", 
		"LAN_PLAYER_COUNT": "Players: {0}/{1}", 
		"LAN_TAG_HOST": "(host)", 
		"LAN_TAG_YOU": "(you)", 
		"LAN_TAG_DISCONNECTED": "(disconnected)", 
	}, 
	"de": {
		"MENU_MULTIPLAYER": "Mehrspieler", 
		"LAN_REJECT_VERSION": "Der Host nutzt eine andere Version der LAN-Coop-Mod.", 
		"LAN_REJECT_GAME_VERSION": "Der Host nutzt eine andere Version von Brotato.", 
		"LAN_REJECT_DLC": "Beim Host sind andere DLCs aktiviert.", 
		"LAN_REJECT_FULL": "Die Lobby ist voll.", 
		"LAN_REJECT_IN_PROGRESS": "Es läuft bereits eine Runde.", 
		"LAN_REJECT_BAD_HELLO": "Der Host konnte die Beitrittsanfrage nicht lesen.", 
		"LAN_MSG_HOST_LEFT": "Der Host hat die Sitzung beendet.", 
		"LAN_MSG_CONNECTION_FAILED": "Verbindung zum Host fehlgeschlagen.", 
		"LAN_MSG_SERVER_FAILED": "Server konnte nicht gestartet werden. Ist der Port schon belegt?", 
		"LAN_MSG_INVALID_IP": "Bitte eine gültige IP-Adresse eingeben.", 
		"LAN_MSG_INVALID_PORT": "Bitte einen Port zwischen 1 und 65535 eingeben.", 
		"LAN_MULTIPLAYER_TITLE": "LAN-Mehrspieler", 
		"LAN_NAME": "Name", 
		"LAN_HOST_IP": "Host-IP", 
		"LAN_PORT": "Port", 
		"LAN_HOST": "Hosten", 
		"LAN_JOIN": "Beitreten", 
		"LAN_CONNECTING": "Verbinde mit {0}...", 
		"LAN_LOBBY": "Lobby", 
		"LAN_LEAVE": "Verlassen", 
		"LAN_JOIN_ADDRESS": "Andere treten bei über: {0} (Port {1})", 
		"LAN_PLAYER_COUNT": "Spieler: {0}/{1}", 
		"LAN_TAG_HOST": "(Host)", 
		"LAN_TAG_YOU": "(du)", 
		"LAN_TAG_DISCONNECTED": "(getrennt)", 
	}, 
}


static func register() -> void :
	for locale in STRINGS:
		var translation: = Translation.new()
		translation.locale = locale
		var strings: Dictionary = STRINGS[locale]
		for key in strings:
			translation.add_message(key, strings[key])
		TranslationServer.add_translation(translation)
