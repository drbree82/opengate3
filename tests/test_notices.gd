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


func test_full_text(t) -> void:
	var text := Notices.full_text()
	for heading in ["THIS GAME", "GODOT ENGINE", "THIRD-PARTY COMPONENTS OF GODOT ENGINE", "LICENCE TEXT: Expat"]:
		t.ok(text.contains(heading), "full text has the section '%s'" % heading)
	t.ok(text.contains(Engine.get_license_text().strip_edges()), "full text carries Godot's licence")
	t.ok(text.length() > 20000, "full text carries the component licence texts")
