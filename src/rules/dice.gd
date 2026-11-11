class_name Dice
extends RefCounted
## Dice expressions: "1d20", "2d6+3", "1d8+1d6-1", "5".
## A parsed expression is {terms: [{count, sides, sign}], flat: int}.
##
## A "roll result" Dictionary is what the dice tray displays. Every roll in the game uses this shape:
##   kind     "check" | "attack" | "damage" | "save" | "initiative" | "heal" | "raw"
##   label    what was rolled, e.g. "Perception"
##   actor    who rolled, e.g. "Pip"
##   dice     [{sides, value}]  the physical dice shown in the tray
##   parts    [{label, value}]  the modifier breakdown
##   modifier sum of parts, total = dice + modifier
##   dc/success  present for checks against a target number
##   natural  the d20 face (d20 rolls only), crit/fumble flags, note (free text)

static var _re: RegEx


static func parse(expr) -> Dictionary:
	var s := str(expr).replace(" ", "").to_lower()
	var terms: Array = []
	var flat := 0
	if _re == null:
		_re = RegEx.new()
		_re.compile("([+-]?)(?:(\\d*)d(\\d+)|(\\d+))")
	var consumed := 0
	for m in _re.search_all(s):
		var sgn := -1 if m.get_string(1) == "-" else 1
		if m.get_string(3) != "":
			var cnt := 1 if m.get_string(2) == "" else int(m.get_string(2))
			terms.append({"count": cnt, "sides": int(m.get_string(3)), "sign": sgn})
		else:
			flat += sgn * int(m.get_string(4))
		consumed += m.get_string(0).length()
	if consumed != s.length():
		push_error("Bad dice expression: '%s'" % str(expr))
	return {"terms": terms, "flat": flat}


static func format(parsed: Dictionary) -> String:
	var out := ""
	for t in parsed.terms:
		var piece := "%dd%d" % [t.count, t.sides]
		if out == "":
			out = ("-" if t.sign < 0 else "") + piece
		else:
			out += ("-" if t.sign < 0 else "+") + piece
	var flat: int = parsed.flat
	if out == "":
		return str(flat)
	if flat > 0:
		out += "+%d" % flat
	elif flat < 0:
		out += str(flat)
	return out


## "1d8" + 3 -> "1d8+3"
static func add_flat(expr, n: int) -> String:
	var p := parse(expr)
	p.flat += n
	return format(p)


## Average result, rounded down (used for monster hit points and AI estimates).
static func average(expr) -> int:
	var p := parse(expr)
	var total := float(p.flat)
	for t in p.terms:
		total += t.sign * t.count * (t.sides + 1) / 2.0
	return floori(total)


## Rolls an expression. `times` repeats the whole expression (used for critical hits).
## Returns {expr, dice: [{sides, value, sign}], flat, total}.
static func roll(expr, rng: Rng, times: int = 1) -> Dictionary:
	var p := parse(expr)
	var dice: Array = []
	var total := 0
	for i in times:
		for t in p.terms:
			for j in t.count:
				var v := rng.die(t.sides)
				dice.append({"sides": t.sides, "value": v, "sign": t.sign})
				total += t.sign * v
		total += p.flat
	return {"expr": str(expr), "dice": dice, "flat": p.flat * times, "total": total}


## Wraps a Dice.roll() into the roll-result shape shown by the dice tray.
static func as_result(rolled: Dictionary, kind: String, label: String, actor: String, note := "") -> Dictionary:
	var parts: Array = []
	if rolled.flat != 0:
		parts.append({"label": "Bonus", "value": rolled.flat})
	return {
		"kind": kind, "label": label, "actor": actor, "dice": rolled.dice, "parts": parts,
		"modifier": rolled.flat, "total": rolled.total, "note": note,
	}
