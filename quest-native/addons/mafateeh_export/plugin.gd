@tool
extends EditorPlugin
## Editor-only: adds the manifest entries the Meta Horizon Store requires.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/mafateeh_export/manifest_export.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
