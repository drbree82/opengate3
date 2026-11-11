class_name Notices
extends RefCounted
## Licence and copyright notices that the game must be able to show. Read docs/LICENSING.md first.
##
## Godot Engine is MIT-licensed. A game that ships the engine has to show Godot's copyright notice and
## licence text, and the notices of the libraries that are built into the engine. All of that text is
## asked from the RUNNING engine (Engine.get_license_text() and friends), so it always matches the Godot
## version inside the build and nothing has to be edited by hand when Godot is upgraded.
##
## Used by:  src/ui/licenses_screen.gd   (title screen / pause menu -> "Licences")
##           tools/write_notices.gd      (writes the same text to a file to ship next to an exported build)
## Adding your own asset or library? List it in THIRD_PARTY_NOTICES.md (repo root), not in this file.

## This game's own licence and its own third-party list. Both are plain text files in the repo root.
## An exported build only contains them if the export preset's include filter lists them
## (docs/LICENSING.md); FALLBACK_* is shown when they are missing.
const PROJECT_LICENSE := "res://LICENSE"
const PROJECT_NOTICES := "res://THIRD_PARTY_NOTICES.md"
const FALLBACK_LICENSE := "OpenGate is released under the MIT License. The full text is in the LICENSE file that comes with the game."
const FALLBACK_NOTICES := "The list of third-party material is in the THIRD_PARTY_NOTICES.md file that comes with the game."
const GODOT_LICENSE_URL := "https://godotengine.org/license"
const RULE := "------------------------------------------------------------------------"


static func _read(path: String, fallback: String) -> String:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path).strip_edges()
		if text != "":
			return text
	return fallback


## The game's own licence (the LICENSE file).
static func project() -> String:
	return _read(PROJECT_LICENSE, FALLBACK_LICENSE)


## The game's own list of third-party material (THIRD_PARTY_NOTICES.md).
static func project_notices() -> String:
	return _read(PROJECT_NOTICES, FALLBACK_NOTICES)


static func godot_version() -> String:
	return str(Engine.get_version_info().get("string", ""))


## Godot's copyright notice and licence text, plus the FreeType credit line that its licence asks for.
static func engine() -> String:
	var lines: Array = []
	lines.append("This game uses Godot Engine %s." % godot_version())
	lines.append("Godot Engine is free and open source software, available under the following license (%s):" % GODOT_LICENSE_URL)
	lines.append("")
	lines.append(Engine.get_license_text().strip_edges())
	var ft := freetype_credit()
	if ft != "":
		lines.append("")
		lines.append(ft)
	return "\n".join(lines)


## "Portions of this software are copyright (c) <year> The FreeType Project ..." - the credit that the
## FreeType licence asks for (Godot draws all text with FreeType). "" if this engine build has no FreeType.
static func freetype_credit() -> String:
	for comp in components():
		if not str(comp.name).to_lower().contains("freetype"):
			continue
		var year := 0
		var re := RegEx.new()
		re.compile("\\d{4}")
		for line in comp.copyright:
			for m in re.search_all(str(line)):
				year = maxi(year, int(m.get_string()))
		return "Portions of this software are copyright (c) %sThe FreeType Project (www.freetype.org). All rights reserved." % (("%d " % year) if year > 0 else "")
	return ""


## Every component built into the engine: [{name, licenses: [String], copyright: [String]}]
## (the first entry is Godot itself).
static func components() -> Array:
	var out: Array = []
	for comp in Engine.get_copyright_info():
		var licenses: Array = []
		var holders: Array = []
		for part in comp.get("parts", []):
			var lic := str(part.get("license", ""))
			if lic != "" and not licenses.has(lic):
				licenses.append(lic)
			for line in part.get("copyright", []):
				if not holders.has(str(line)):
					holders.append(str(line))
		out.append({"name": str(comp.get("name", "?")), "licenses": licenses, "copyright": holders})
	return out


## The component list as readable text.
static func components_text() -> String:
	var lines: Array = []
	lines.append("Godot Engine contains the following third-party components. Each is listed with its")
	lines.append("copyright holders and its licence; the full licence texts follow under \"Licence texts\".")
	for comp in components():
		lines.append("")
		lines.append("%s   [%s]" % [comp.name, ", ".join(comp.licenses)])
		for line in comp.copyright:
			lines.append("    (c) " + line)
	return "\n".join(lines)


## Names of the licences used by the engine and its components, sorted ("Expat" is the MIT licence).
static func license_ids() -> Array:
	var ids: Array = Engine.get_license_info().keys()
	ids.sort()
	return ids


## Full text of one licence from license_ids(), or "".
static func license_text(id: String) -> String:
	return str(Engine.get_license_info().get(id, "")).strip_edges()


## Everything in one text: this game's licence and notices, Godot's licence, the component list and every
## licence text. tools/write_notices.gd saves this next to an exported build.
static func full_text() -> String:
	var parts: Array = []
	parts.append("LICENCES AND THIRD-PARTY NOTICES")
	parts.append(RULE + "\nTHIS GAME\n" + RULE + "\n" + project())
	parts.append(RULE + "\nTHIRD-PARTY MATERIAL IN THIS GAME\n" + RULE + "\n" + project_notices())
	parts.append(RULE + "\nGODOT ENGINE\n" + RULE + "\n" + engine())
	parts.append(RULE + "\nTHIRD-PARTY COMPONENTS OF GODOT ENGINE\n" + RULE + "\n" + components_text())
	for id in license_ids():
		parts.append(RULE + "\nLICENCE TEXT: " + str(id) + "\n" + RULE + "\n" + license_text(id))
	return "\n\n".join(parts) + "\n"
