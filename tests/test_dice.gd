extends RefCounted
## Tests for src/rules/dice.gd and src/core/rng.gd


func test_parse(t) -> void:
	var p := Dice.parse("2d6+3")
	t.eq(p.terms.size(), 1, "one dice term")
	t.eq(p.terms[0].count, 2, "count")
	t.eq(p.terms[0].sides, 6, "sides")
	t.eq(p.flat, 3, "flat bonus")
	t.eq(Dice.parse("d20").terms[0].count, 1, "implicit count")
	t.eq(Dice.parse("1d8+1d6-1").terms.size(), 2, "two terms")
	t.eq(Dice.parse("1d8+1d6-1").flat, -1, "negative flat")
	t.eq(Dice.parse("5").flat, 5, "plain number")


func test_format_and_add(t) -> void:
	t.eq(Dice.add_flat("1d8", 3), "1d8+3", "add bonus")
	t.eq(Dice.add_flat("1d4", -1), "1d4-1", "add penalty")
	t.eq(Dice.add_flat("1d6+2", -2), "1d6", "bonus cancels")
	t.eq(Dice.average("2d6+3"), 10, "average")


func test_roll(t) -> void:
	var r := Dice.roll("2d6+3", Rng.fixed([4, 5]))
	t.eq(r.total, 12, "2d6+3 with 4,5")
	t.eq(r.dice.size(), 2, "two dice shown")
	var crit := Dice.roll("1d8+2", Rng.fixed([3, 6]), 2)
	t.eq(crit.total, 13, "crit doubles dice and bonus")
	var real := Rng.new(42)
	for i in 200:
		var v := real.die(20)
		t.ok(v >= 1 and v <= 20, "d20 in range")
