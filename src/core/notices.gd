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

## This game's own licence, its own third-party list and the Open Game License notice for the rules.
## All three are plain text files in the repo root.
## An exported build only contains them if the export preset's include filter lists them
## (docs/LICENSING.md); FALLBACK_* is shown when they are missing.
const PROJECT_LICENSE := "res://LICENSE"
const PROJECT_NOTICES := "res://THIRD_PARTY_NOTICES.md"
## The Open Game License notice for the Pathfinder rules data: which parts are Open Game Content, the
## full licence text and its Section 15 copyright notices. It must travel with the rules data.
const RULES_LICENSE := "res://OGL.txt"
const FALLBACK_LICENSE := "OpenGate is released under the MIT License. The full text is in the LICENSE file that comes with the game."
const FALLBACK_NOTICES := "The list of third-party material is in the THIRD_PARTY_NOTICES.md file that comes with the game."
const FALLBACK_RULES := "The game rules are Open Game Content, used under the Open Game License version 1.0a. The full licence text and its copyright notices are in the OGL.txt file that comes with the game."
const GODOT_LICENSE_URL := "https://godotengine.org/license"

## --- Paizo Community Use Policy (docs/LICENSING.md, "The name Pathfinder") -------------------------
## The project refers to Paizo's trademarks ("Pathfinder") under Paizo's Community Use Policy. That policy
## prescribes the notice below WORD FOR WORD (only the product name is ours) and asks for visible contact
## information. Never reword PAIZO_NOTICE; README.md carries the same text and tests/test_notices.gd
## checks that the two match. A fork must use its own name and contact address here (the permission is
## personal to each project) or stop using Paizo's trademarks.
const PRODUCT_NAME := "OpenGate"
const PAIZO_NOTICE := "%s uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community Use Policy (paizo.com/licenses/communityuse). We are expressly prohibited from charging you to use or access this content. %s is not published, endorsed, or specifically approved by Paizo. For more information about Paizo Inc. and Paizo products, visit paizo.com."
const PAIZO_TRADEMARKS := "Pathfinder and Pathfinder Roleplaying Game are trademarks of Paizo Inc."
## Where to reach the people behind this project (the policy asks for up-to-date contact information).
const CONTACT_URL := "https://github.com/drbree82/opengate3/issues"
## One line for the title screen; the full notice is on the Licences screen.
const PAIZO_SHORT := "An unofficial, free fan project. Uses trademarks owned by Paizo Inc. under Paizo's Community Use Policy - not published, endorsed or approved by Paizo. See Licences."
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


## The Open Game License notice for the game rules (OGL.txt). Never edit the licence wording in that file.
static func rules_license() -> String:
	return _read(RULES_LICENSE, FALLBACK_RULES)


## The notice Paizo's Community Use Policy prescribes, with this project's name filled in.
static func paizo_notice() -> String:
	return PAIZO_NOTICE % [PRODUCT_NAME, PRODUCT_NAME]


## Everything the Community Use Policy asks a project to show: the notice, Paizo's trademark line and
## where to contact the project.
static func community_use() -> String:
	return "%s\n\n%s\n\nThis game is free. Contact: %s" % [paizo_notice(), PAIZO_TRADEMARKS, CONTACT_URL]


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


## Everything in one text: this game's licence and notices, the Open Game License notice for the rules,
## Godot's licence, the component list and every licence text. tools/write_notices.gd saves this next to an exported build.
static func full_text() -> String:
	var parts: Array = []
	parts.append("LICENCES AND THIRD-PARTY NOTICES")
	parts.append(RULE + "\nTHIS GAME\n" + RULE + "\n" + project())
	parts.append(RULE + "\nTHIRD-PARTY MATERIAL IN THIS GAME\n" + RULE + "\n" + project_notices())
	parts.append(RULE + "\nPAIZO COMMUNITY USE NOTICE\n" + RULE + "\n" + community_use())
	parts.append(RULE + "\nGAME RULES (OPEN GAME LICENSE)\n" + RULE + "\n" + rules_license())
	parts.append(RULE + "\nGODOT ENGINE\n" + RULE + "\n" + engine())
	parts.append(RULE + "\nTHIRD-PARTY COMPONENTS OF GODOT ENGINE\n" + RULE + "\n" + components_text())
	for id in license_ids():
		parts.append(RULE + "\nLICENCE TEXT: " + str(id) + "\n" + RULE + "\n" + license_text(id))
	return "\n\n".join(parts) + "\n"
