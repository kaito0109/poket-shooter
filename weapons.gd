class_name Weapons
extends RefCounted
## Weapon and ammo definitions shared by the player and bots (PUBG-style).

const DATA: Dictionary = {
	"p92": {
		"name": "P92", "dmg": 15.0, "interval": 0.26, "auto": false, "mag": 15,
		"reload": 1.3, "speed": 115.0, "spread": 1.8, "ammo": "9mm",
		"falloff": 45.0, "kick": 0.5, "ads_fov": 57.0, "len": 0.55, "power": 1,
		"sfx": "shot", "pellets": 1,
	},
	"uzi": {
		"name": "マイクロUZI", "dmg": 12.5, "interval": 0.06, "auto": true, "mag": 25,
		"reload": 2.1, "speed": 125.0, "spread": 3.4, "ammo": "9mm",
		"falloff": 35.0, "kick": 0.28, "ads_fov": 55.0, "len": 0.6, "power": 3,
		"sfx": "shot", "pellets": 1,
	},
	"m416": {
		"name": "M416", "dmg": 23.0, "interval": 0.092, "auto": true, "mag": 30,
		"reload": 1.9, "speed": 215.0, "spread": 1.4, "ammo": "556",
		"falloff": 110.0, "kick": 0.42, "ads_fov": 50.0, "len": 0.95, "power": 4,
		"sfx": "shot", "pellets": 1,
	},
	"s686": {
		"name": "S686", "dmg": 10.0, "interval": 0.9, "auto": false, "mag": 2,
		"reload": 2.3, "speed": 135.0, "spread": 6.0, "ammo": "shell",
		"falloff": 18.0, "kick": 1.6, "ads_fov": 55.0, "len": 1.0, "power": 2,
		"sfx": "shotgun", "pellets": 6,
	},
	"kar98": {
		"name": "Kar98K", "dmg": 74.0, "interval": 1.3, "auto": false, "mag": 5,
		"reload": 3.0, "speed": 330.0, "spread": 0.12, "ammo": "762",
		"falloff": 260.0, "kick": 1.9, "ads_fov": 21.0, "len": 1.25, "power": 5,
		"sfx": "sniper", "pellets": 1,
	},
}

const AMMO_NAMES: Dictionary = {
	"9mm": "9mm弾", "556": "5.56mm弾", "762": "7.62mm弾", "shell": "12ゲージ弾",
}

const AMMO_PACKS: Dictionary = {
	"9mm": 30, "556": 30, "762": 10, "shell": 8,
}

static func get_data(weapon_id: String) -> Dictionary:
	return DATA.get(weapon_id, {})

static func display_name(weapon_id: String) -> String:
	var d: Dictionary = DATA.get(weapon_id, {})
	return String(d.get("name", weapon_id))

static func power(weapon_id: String) -> int:
	var d: Dictionary = DATA.get(weapon_id, {})
	return int(d.get("power", 0))
