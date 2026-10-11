@tool
extends EditorExportPlugin
## The OpenXR Vendors plugin declares headtracking with required="false"
## (it only switches to "true" for boundaryless apps). Store submissions need
## required="true", so replace that entry for every Android export.

func _get_name() -> String:
	return "MafateehManifest"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return '    <uses-feature android:name="android.hardware.vr.headtracking" android:required="true" android:version="1" tools:node="replace" />\n'
