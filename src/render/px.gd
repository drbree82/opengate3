class_name Px
extends RefCounted
## A tiny pixel-art "canvas". Drawing calls only RECORD rectangles; stamp() then paints them into an
## Image twice: first a dark outline (every rectangle grown by one pixel), then the colours on top.
## That gives every sprite a clean 16-bit style outline for free, using only fast Image.fill_rect calls.
##
##   var p := Px.new()
##   p.shaded(10, 4, 12, 20, Color("#7a4030"))   # a body part with a highlight and a shadow edge
##   p.rect(14, 8, 2, 2, Color.BLACK)             # a detail
##   p.stamp(image, frame_x, frame_y, 48, 48)

var ops: Array = []   # [x, y, w, h, Color, outlined]


func rect(x: int, y: int, w: int, h: int, c: Color, outlined := true) -> void:
	if w > 0 and h > 0:
		ops.append([x, y, w, h, c, outlined])


func dot(x: int, y: int, c: Color, outlined := false) -> void:
	ops.append([x, y, 1, 1, c, outlined])


## A rectangle with a lighter left edge and darker right/bottom edges (light from the top left).
func shaded(x: int, y: int, w: int, h: int, c: Color) -> void:
	rect(x, y, w, h, c)
	if w >= 3 and h >= 2:
		rect(x, y, 1, h, c.lightened(0.18), false)
		rect(x + w - 1, y, 1, h, c.darkened(0.22), false)
	if w >= 3 and h >= 4:
		rect(x + 1, y + h - 1, w - 2, 1, c.darkened(0.15), false)


## A filled ellipse built from horizontal strips.
func ellipse(cx: int, cy: int, rx: int, ry: int, c: Color, outlined := true) -> void:
	for dy in range(-ry, ry + 1):
		var k := 1.0 - float(dy * dy) / float(maxi(1, ry * ry))
		var half := int(round(rx * sqrt(maxf(0.0, k))))
		rect(cx - half, cy + dy, half * 2 + 1, 1, c, outlined)


## A straight line of square dots (thickness in pixels).
func line(x0: int, y0: int, x1: int, y1: int, c: Color, thick := 1, outlined := true) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for i in range(steps + 1):
		var t := 0.0 if steps == 0 else float(i) / steps
		rect(int(round(lerpf(x0, x1, t))), int(round(lerpf(y0, y1, t))), thick, thick, c, outlined)


## Paints the recorded shapes into `img` inside the frame at (ox, oy) of size fw x fh.
##   flip    mirror horizontally (a sprite drawn facing right becomes one facing left)
##   lying   rotate the figure onto its side (used for "dead" frames)
func stamp(img: Image, ox: int, oy: int, fw: int, fh: int, flip := false, lying := false, outline := Color(0.09, 0.07, 0.11)) -> void:
	for o in ops:
		if o[5]:
			_fill(img, ox, oy, fw, fh, o[0] - 1, o[1], o[2] + 2, o[3], outline, flip, lying)
			_fill(img, ox, oy, fw, fh, o[0], o[1] - 1, o[2], o[3] + 2, outline, flip, lying)
	for o in ops:
		_fill(img, ox, oy, fw, fh, o[0], o[1], o[2], o[3], o[4], flip, lying)


static func _fill(img: Image, ox: int, oy: int, fw: int, fh: int, x: int, y: int, w: int, h: int, c: Color, flip: bool, lying: bool) -> void:
	if lying:
		# stand-up (x, y) -> lying on the floor along the bottom of the frame
		var nx := y - 2
		var ny := x + fh - 32
		var nw := h
		h = w
		w = nw
		x = nx
		y = ny
	if flip:
		x = fw - x - w
	var x0 := maxi(0, x)
	var y0 := maxi(0, y)
	var x1 := mini(fw, x + w)
	var y1 := mini(fh, y + h)
	if x1 > x0 and y1 > y0:
		img.fill_rect(Rect2i(ox + x0, oy + y0, x1 - x0, y1 - y0), c)
