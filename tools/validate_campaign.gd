extends SceneTree
## Prints the full validation report (errors AND warnings) for campaigns.
##   godot --headless --path . -s res://tools/validate_campaign.gd -- hollowmere
##   godot --headless --path . -s res://tools/validate_campaign.gd            (every campaign)
## Exit code 1 when any campaign has errors. The checks live in src/engine/campaign_validator.gd.


func _initialize() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		for root in Campaign.ROOTS:
			if DirAccess.dir_exists_absolute(root):
				for d in DirAccess.get_directories_at(root):
					ids.append(d)
	var failed := false
	for id in ids:
		var game := Game.new()
		game.instant = true
		print("\n== %s ==" % id)
		if not game.load_campaign(id):
			printerr("  ERROR  could not load campaign.json")
			failed = true
			continue
		var report := CampaignValidator.check(game)
		for e in report.errors:
			printerr("  ERROR  " + e)
		for w in report.warnings:
			print("  warn   " + w)
		print("  %d errors, %d warnings" % [report.errors.size(), report.warnings.size()])
		failed = failed or not report.errors.is_empty()
	quit(1 if failed else 0)
