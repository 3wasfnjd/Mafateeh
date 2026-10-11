class_name StoreEntitlement
extends Node
## Meta Horizon Store entitlement check (Platform SDK via Godot Meta Toolkit).
## Runs only in store builds: CI writes the App ID into the project setting
## mafateeh/store/meta_app_id from the META_APP_ID secret. Sideload/test builds
## have no App ID and skip the check entirely. Gameplay never waits on it.
##
## Policy: if the platform initialises and the store says this user is not
## entitled, the app quits (Meta's recommended behaviour). If the platform
## cannot initialise at all (service unavailable), the player is not punished.

signal finished(result: String)  # "skipped" | "entitled" | "not_entitled" | "unavailable"


func run() -> void:
	var app_id := String(ProjectSettings.get_setting("mafateeh/store/meta_app_id", "")).strip_edges()
	if app_id == "" or OS.get_name() != "Android" or not Engine.has_singleton("MetaPlatformSDK"):
		finished.emit("skipped")
		return
	var sdk = Engine.get_singleton("MetaPlatformSDK")
	var init = await sdk.initialize_platform_async(app_id).completed
	if init.is_error():
		push_warning("Meta Platform SDK unavailable: %s" % str(init.error))
		finished.emit("unavailable")
		return
	var ent = await sdk.entitlement_get_is_viewer_entitled_async().completed
	if ent.is_error():
		push_warning("User is not entitled to this app: %s" % str(ent.error))
		finished.emit("not_entitled")
		get_tree().quit()
		return
	finished.emit("entitled")
