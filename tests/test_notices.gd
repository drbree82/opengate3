extends RefCounted
## Tests for src/core/notices.gd: the licence notices the game must be able to show (docs/LICENSING.md).
## If one of these fails after a Godot upgrade or a file move, a distributed build would be missing a
## notice it is required to carry - fix the cause, do not delete the test.


func test_engine_notice(t) -> void:
	var text := Notices.engine()
	t.ok(text.contains("Godot Engine"), "names the engine")
	t.ok(text.contains(Notices.godot_version()), "names the engine version in use")
	t.ok(text.contains(Engine.get_license_text().strip_edges()), "contains Godot's full licence text")
	t.ok(text.contains("Permission is hereby granted"), "the licence text is the MIT/Expat grant")
	t.ok(text.contains(Notices.GODOT_LICENSE_URL), "links to godotengine.org/license")


func test_components(t) -> void:
	var comps := Notices.components()
	t.ok(comps.size() > 10, "the engine lists its third-party components")
	t.eq(comps[0].name, "Godot Engine", "Godot itself comes first")
	var known := Notices.license_ids()
	var missing: Array = []
	for comp in comps:
		t.ok(not comp.licenses.is_empty(), "%s has a licence" % comp.name)
		t.ok(not comp.copyright.is_empty(), "%s has a copyright line" % comp.name)
		for lic in comp.licenses:
			# a component may say "A and B" / "A or B": every named licence needs a text
			for id in str(lic).replace(" and ", "|").replace(" or ", "|").split("|"):
				if not known.has(id.strip_edges()) and not id.strip_edges().begins_with("public-domain"):
					missing.append("%s: %s" % [comp.name, id])
	t.eq(missing, [], "every licence named by a component has a full text")
	t.ok(Notices.components_text().contains("FreeType"), "FreeType is credited in the component list")
	t.ok(Notices.freetype_credit().contains("The FreeType Project"), "FreeType credit line")


func test_license_texts(t) -> void:
	var ids := Notices.license_ids()
	t.ok(ids.has("Expat"), "the MIT (Expat) text is available")
	for id in ids:
		t.ok(Notices.license_text(id).length() > 200, "licence text for %s" % id)
	t.eq(Notices.license_text("no-such-licence"), "", "unknown id gives an empty string")


func test_project_files(t) -> void:
	t.ok(FileAccess.file_exists(Notices.PROJECT_LICENSE), "LICENSE exists in the repo root")
	t.ok(FileAccess.file_exists(Notices.PROJECT_NOTICES), "THIRD_PARTY_NOTICES.md exists in the repo root")
	t.ok(Notices.project().contains("MIT License"), "the game's own licence is the MIT licence")
	t.ok(Notices.project() != Notices.FALLBACK_LICENSE, "LICENSE is read, not the fallback")
	var notes := Notices.project_notices()
	t.ok(notes.contains("Godot Engine"), "THIRD_PARTY_NOTICES.md covers Godot Engine")
	t.ok(notes.contains("ElevenLabs"), "THIRD_PARTY_NOTICES.md covers the generated audio")
	t.ok(notes.contains("OGL.txt"), "THIRD_PARTY_NOTICES.md points to the Open Game License notice")


## OGL.txt: the Open Game License for the Pathfinder rules data. Its wording must never change; only
## Section 15 grows when rules content from another book is added (docs/LICENSING.md).
func test_open_game_license(t) -> void:
	t.ok(FileAccess.file_exists(Notices.RULES_LICENSE), "OGL.txt exists in the repo root")
	var text := Notices.rules_license()
	t.ok(text != Notices.FALLBACK_RULES, "OGL.txt is read, not the fallback")
	t.ok(text.contains("DESIGNATION OF OPEN GAME CONTENT"), "says which parts are Open Game Content")
	var start := text.find("OPEN GAME LICENSE Version 1.0a")
	var s15 := text.find("15. COPYRIGHT NOTICE")
	t.ok(start >= 0 and s15 > start, "licence heading and Section 15 are present")
	if start < 0 or s15 <= start:
		return
	# the licence itself (heading .. end of section 14), compared without line breaks
	var re := RegEx.new()
	re.compile("\\s+")
	var body := re.sub(text.substr(start, s15 - start), " ", true).strip_edges()
	t.eq(body.sha256_text(), "21d786a654d675532025362c566c445f430a3d1655e51f3d1c45740accd4db31",
		"the licence wording is unchanged (never edit it - restore OGL.txt from git if this fails)")
	for n in range(1, 15):
		t.ok(body.contains(" %d. " % n), "section %d is present" % n)
	var notices := text.substr(s15)
	for title in ["Open Game License v 1.0a", "System Reference Document", "Pathfinder Roleplaying Game Reference Document",
			"Pathfinder Roleplaying Game Core Rulebook", "Pathfinder Roleplaying Game Bestiary", "OpenGate"]:
		t.ok(notices.contains("\n" + title), "Section 15 has the notice for '%s'" % title)


## Paizo Community Use Policy: the prescribed notice must be in the game and in the README, word for word.
func test_paizo_community_use_notice(t) -> void:
	var notice := Notices.paizo_notice()
	t.ok(notice.begins_with("OpenGate uses trademarks and/or copyrights owned by Paizo Inc."), "names the product and Paizo")
	for phrase in ["used under Paizo's Community Use Policy (paizo.com/licenses/communityuse)",
			"We are expressly prohibited from charging you to use or access this content.",
			"OpenGate is not published, endorsed, or specifically approved by Paizo.",
			"For more information about Paizo Inc. and Paizo products, visit paizo.com."]:
		t.ok(notice.contains(phrase), "the notice keeps Paizo's wording: '%s'" % phrase)
	t.ok(not notice.contains("%s"), "the product name is filled in")
	var shown := Notices.community_use()
	t.ok(shown.contains(notice), "the Licences screen text carries the notice")
	t.ok(shown.contains(Notices.PAIZO_TRADEMARKS), "... and Paizo's trademark line")
	t.ok(shown.contains(Notices.CONTACT_URL), "... and the contact address")
	t.ok(Notices.CONTACT_URL.begins_with("https://"), "the contact address is a link")
	t.ok(Notices.PAIZO_SHORT.contains("Community Use Policy") and Notices.PAIZO_SHORT.contains("not published, endorsed or approved by Paizo"),
		"the title-screen line names the policy and says the game is unofficial")
	var readme := FileAccess.get_file_as_string("res://README.md")
	t.ok(readme.contains(notice), "README.md carries exactly the same notice as the game")
	t.ok(readme.contains(Notices.PAIZO_TRADEMARKS), "README.md carries Paizo's trademark line")
	t.ok(readme.contains(Notices.CONTACT_URL), "README.md shows the contact address")
	t.ok(Notices.project_notices().contains(notice), "THIRD_PARTY_NOTICES.md carries the notice")


func test_full_text(t) -> void:
	var text := Notices.full_text()
	for heading in ["THIS GAME", "GAME RULES (OPEN GAME LICENSE)", "GODOT ENGINE", "THIRD-PARTY COMPONENTS OF GODOT ENGINE", "LICENCE TEXT: Expat"]:
		t.ok(text.contains(heading), "full text has the section '%s'" % heading)
	t.ok(text.contains(Engine.get_license_text().strip_edges()), "full text carries Godot's licence")
	t.ok(text.contains("OPEN GAME LICENSE Version 1.0a"), "full text carries the Open Game License")
	t.ok(text.contains(Notices.paizo_notice()), "full text carries the Paizo Community Use notice")
	t.ok(text.length() > 20000, "full text carries the component licence texts")
