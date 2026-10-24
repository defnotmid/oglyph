// The oglyph mascot: a 32x32 pixel-art octopus holding a quill, in the family
// of onimite's Pip, odecs' turntable, ottis' Ottis, ovg's chameleon and oksl's
// firefly. An octopus because oglyph is ink and curves: its arms curl like
// strokes of a script, and it writes with one of them. Writes an SVG whose
// parts are groups a script shows or hides by id (onimite:
// svg{ overrides = { eyes_closed = { visible = true } } }):
//
//   body          outline, head, arms, suckers and the quill (on)
//   eyes_open     big eyes with two shines (on)   eyes_closed  a happy blink
//   eyes_o        round surprised eyes
//   mouth_smile   a small smile (on)              mouth_o      a little "o"
//   ink_1 ink_2 ink_3  a drop of ink forming at the nib, falling, splashed (off)
//   silhouette    every visible pixel as one outline (off): the shape to
//                 morph, extrude or collide (onimite: outline{ svg = "logo.svg", id = "silhouette" })
//
// Each layer is one path per colour, its pixels traced into merged outlines.
//
// Also writes the project logo as PNGs, scaled without smoothing:
//
//   odin run tools/mascot -- assets   (assets/logo.svg, logo.png 256 px, logo_32x32.png)
package mascot

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import stbi "vendor:stb/image"

W :: 32
H :: 32

Grid :: [H][W]u8 // palette keys, '.' empty

color :: proc(c: u8) -> string {
	switch c {
	case 'O': return "#1e1638" // outline
	case 'B': return "#8a6cf0" // body
	case 'D': return "#5e46c8" // body shade
	case 'H': return "#b9a6ff" // body highlight
	case 'S': return "#f7b6e9" // suckers
	case 'E': return "#1b1220" // eyes
	case 'W': return "#ffffff" // shines
	case 'K': return "#ff9db4" // cheeks
	case 'M': return "#3b1745" // mouth
	case 'Q': return "#fff4dc" // feather
	case 'q': return "#e2c896" // feather shade, shaft
	case 'N': return "#f2b84b" // nib
	case 'I': return "#36c6f0" // ink
	case 'i': return "#1f86c4" // ink shade
	}
	return "#ff00ff"
}

empty :: proc() -> (g: Grid) {
	for &row in g do for &p in row do p = '.'
	return
}

put :: proc(g: ^Grid, x, y: int, c: u8) {
	if 0 <= x && x < W && 0 <= y && y < H do g[y][x] = c
}

in_ellipse :: proc(x, y: int, cx, cy, rx, ry: f64) -> (bool, f64, f64) {
	u := (f64(x) + 0.5 - cx) / rx
	v := (f64(y) + 0.5 - cy) / ry
	return u * u + v * v <= 1, u, v
}

// Fills an ellipse: shade along the lower rim, highlight upper left.
skin :: proc(g: ^Grid, cx, cy, rx, ry: f64) {
	for y in 0 ..< H do for x in 0 ..< W {
		inside, u, v := in_ellipse(x, y, cx, cy, rx, ry)
		if !inside do continue
		c := u8('B')
		if u * u + v * v > 0.55 && u * 0.3 + v * 0.95 > 0.4 do c = 'D'
		else if u * u + v * v > 0.45 && u * 0.4 + v * 0.9 < -0.55 do c = 'H'
		put(g, x, y, c)
	}
}

// Fills the pixels within a radius of the polyline `pts`, the radius tapering
// from r0 at its first point to r1 at its last, with `c`.
stroke :: proc(g: ^Grid, pts: [][2]f64, r0, r1: f64, c: u8, frac: ^[H][W]f64 = nil) {
	total: f64
	for i in 1 ..< len(pts) do total += math.sqrt((pts[i].x - pts[i - 1].x) * (pts[i].x - pts[i - 1].x) + (pts[i].y - pts[i - 1].y) * (pts[i].y - pts[i - 1].y))
	for y in 0 ..< H do for x in 0 ..< W {
		p := [2]f64{f64(x) + 0.5, f64(y) + 0.5}
		along: f64
		for i in 1 ..< len(pts) {
			a, b := pts[i - 1], pts[i]
			ab := b - a
			l := math.sqrt(ab.x * ab.x + ab.y * ab.y)
			t := clamp(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / (l * l), 0, 1)
			q := a + ab * t
			d := math.sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y))
			r := r0 + (r1 - r0) * (along + l * t) / total
			if d <= r {
				put(g, x, y, c)
				if frac != nil do frac[y][x] = (along + l * t) / total
				break
			}
			along += l
		}
	}
}

// An arm: a tapering stroke, shaded along its lower edge, with suckers
// along that edge towards the tip.
arm :: proc(g: ^Grid, pts: [][2]f64, r0, r1: f64) {
	a := empty()
	frac: [H][W]f64
	stroke(&a, pts, r0, r1, 'B', &frac)
	for y in 0 ..< H do for x in 0 ..< W {
		if a[y][x] == '.' do continue
		if y + 1 < H && a[y + 1][x] != '.' do continue
		a[y][x] = 'S' if frac[y][x] > 0.45 && (x + y) % 2 == 0 else 'D'
	}
	over(g, a)
}

// Outlines every filled pixel's empty 4-neighbours.
outline :: proc(g: ^Grid) {
	src := g^
	for y in 0 ..< H do for x in 0 ..< W {
		if src[y][x] != '.' do continue
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			nx, ny := x + d.x, y + d.y
			if 0 <= nx && nx < W && 0 <= ny && ny < H && src[ny][nx] != '.' && src[ny][nx] != 'O' {
				g[y][x] = 'O'
				break
			}
		}
	}
}

// Draws `fg` over `g`, outlining fg's shapes against everything else.
over :: proc(g: ^Grid, fg: Grid) {
	shape := fg
	outline(&shape)
	for y in 0 ..< H do for x in 0 ..< W do if shape[y][x] != '.' do g[y][x] = shape[y][x]
}

// The quill's line, from the nib's tip up to the feather's tip.
NIB :: [2]f64{30.0, 22.0}
TIP :: [2]f64{26.4, 1.6}

draw_body :: proc() -> Grid {
	g := empty()

	// The quill: a feather on a shaft, the nib below the arm that holds it.
	quill := empty()
	for y in 0 ..< H do for x in 0 ..< W {
		p := [2]f64{f64(x) + 0.5, f64(y) + 0.5}
		t := (p.y - TIP.y) / (NIB.y - TIP.y) // 0 at the feather's tip, 1 at the nib
		if t < 0 || t > 1 do continue
		off := p.x - (TIP.x + (NIB.x - TIP.x) * t)
		vane := 1.9 * math.sin(math.PI * clamp(t / 0.62, 0, 1)) // the feather, widest a third down
		switch {
		case t < 0.62 && abs(off) <= vane + 0.5: put(&quill, x, y, 'q' if abs(off) < 0.5 || off > vane - 0.6 else 'Q')
		case t >= 0.62 && t < 0.82 && abs(off) < 0.6: put(&quill, x, y, 'q')
		case t >= 0.82 && abs(off) < 0.6 + 0.4 * (1 - t) / 0.18: put(&quill, x, y, 'N')
		}
	}
	over(&g, quill)

	// The arm holding it, curled round the shaft.
	arm(&g, {{22.0, 15.0}, {25.0, 16.2}, {27.6, 15.6}, {28.8, 14.0}, {27.6, 12.6}}, 1.8, 0.8)

	// Four arms below, spreading and curling up at the tips, and one waving.
	arm(&g, {{11.0, 17.0}, {8.4, 20.0}, {5.6, 22.4}, {3.4, 24.4}, {2.4, 26.8}, {3.4, 28.6}, {5.2, 28.2}}, 2.0, 0.8)
	arm(&g, {{13.8, 18.0}, {12.6, 22.2}, {11.0, 25.6}, {10.4, 28.2}, {11.6, 29.6}, {13.0, 28.8}}, 2.0, 0.8)
	arm(&g, {{17.2, 18.0}, {18.4, 22.2}, {20.0, 25.6}, {20.6, 28.2}, {19.4, 29.6}, {18.0, 28.8}}, 2.0, 0.8)
	arm(&g, {{20.0, 17.0}, {22.6, 20.0}, {25.0, 22.4}, {26.8, 24.6}, {27.4, 27.0}, {26.2, 28.8}, {24.4, 28.2}}, 2.0, 0.8)
	arm(&g, {{9.0, 14.6}, {6.0, 14.2}, {4.2, 12.2}, {3.8, 9.4}, {2.8, 7.4}, {1.4, 7.8}}, 1.8, 0.8)

	// The head, a tall dome, with a few spots.
	head := empty()
	skin(&head, 15.5, 11.0, 8.2, 8.4)
	for p in ([?][2]int{{18, 5}, {19, 5}, {20, 7}, {11, 6}}) do if head[p.y][p.x] == 'B' do put(&head, p.x, p.y, 'H')
	put(&head, 9, 14, 'K')
	put(&head, 10, 14, 'K')
	put(&head, 21, 14, 'K')
	put(&head, 22, 14, 'K')
	over(&g, head)
	return g
}

draw_eyes :: proc() -> (open, closed, round: Grid) {
	open, closed, round = empty(), empty(), empty()
	for ex in ([2]int{11, 18}) {
		for y in 10 ..< 14 do for x in ex ..< ex + 3 do put(&open, x, y, 'E')
		put(&open, ex, 10, 'W')
		put(&open, ex + 1, 10, 'W')
		put(&open, ex + 2, 13, 'W')
		put(&closed, ex, 12, 'E')
		put(&closed, ex + 1, 11, 'E')
		put(&closed, ex + 2, 12, 'E')
		for y in 9 ..< 14 do for x in ex - 1 ..< ex + 4 {
			if (y == 9 || y == 13) && (x == ex - 1 || x == ex + 3) do continue
			put(&round, x, y, 'E')
		}
		put(&round, ex, 10, 'W')
		put(&round, ex + 1, 10, 'W')
		put(&round, ex, 11, 'W')
	}
	return
}

draw_mouths :: proc() -> (smile, o: Grid) {
	smile, o = empty(), empty()
	for p in ([?][2]int{{14, 15}, {15, 16}, {16, 16}, {17, 15}}) do put(&smile, p.x, p.y, 'M')
	for p in ([?][2]int{{15, 15}, {16, 15}, {15, 16}, {16, 16}}) do put(&o, p.x, p.y, 'M')
	return
}

// A drop of ink at the nib: forming, falling, splashed on the ground.
draw_ink :: proc() -> (forming, falling, splash: Grid) {
	forming, falling, splash = empty(), empty(), empty()
	put(&forming, 30, 22, 'I')
	put(&forming, 30, 23, 'i')
	for p in ([?][2]int{{30, 25}, {30, 26}, {29, 26}, {31, 26}, {30, 27}}) do put(&falling, p.x, p.y, 'I')
	put(&falling, 31, 27, 'i')
	for p in ([?][2]int{{27, 29}, {28, 29}, {29, 29}, {30, 29}, {31, 29}, {28, 28}, {30, 28}, {26, 28}}) do put(&splash, p.x, p.y, 'I')
	put(&splash, 29, 29, 'i')
	return
}

main :: proc() {
	dir := os.args[1] if len(os.args) > 1 else "assets"
	body := draw_body()
	eyes_open, eyes_closed, eyes_o := draw_eyes()
	mouth_smile, mouth_o := draw_mouths()
	ink_1, ink_2, ink_3 := draw_ink()
	layers := []Layer {
		{"body", body, true},
		{"eyes_open", eyes_open, true},
		{"eyes_closed", eyes_closed, false},
		{"eyes_o", eyes_o, false},
		{"mouth_smile", mouth_smile, true},
		{"mouth_o", mouth_o, false},
		{"ink_1", ink_1, false},
		{"ink_2", ink_2, false},
		{"ink_3", ink_3, false},
	}
	join :: proc(dir, name: string) -> string {
		p, _ := filepath.join({dir, name}, context.temp_allocator)
		return p
	}
	if err := os.write_entire_file(join(dir, "logo.svg"), svg(layers)); err != nil {
		fmt.eprintfln("writing %s: %v", join(dir, "logo.svg"), err)
		os.exit(1)
	}
	if !png(join(dir, "logo.png"), layers, 8) || !png(join(dir, "logo_32x32.png"), layers, 1) {
		fmt.eprintln("writing the PNGs failed")
		os.exit(1)
	}
}

Layer :: struct {
	name: string,
	grid: Grid,
	on:   bool,
}

// Each layer's pixels of one colour as one path, and the visible layers'
// union as `silhouette` (off): the whole octopus as one outline, for
// morphing, extruding or colliding.
svg :: proc(layers: []Layer) -> string {
	b := strings.builder_make()
	fmt.sbprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" shape-rendering="crispEdges">`, W, H, W * 8, H * 8)
	strings.write_byte(&b, '\n')
	for l in layers {
		fmt.sbprintf(&b, `<g id="%s"%s>`, l.name, "" if l.on else ` display="none"`)
		done: [256]bool
		for y in 0 ..< H do for x in 0 ..< W {
			c := l.grid[y][x]
			if c == '.' || done[c] do continue
			done[c] = true
			mask: Mask
			for yy in 0 ..< H do for xx in 0 ..< W do mask[yy][xx] = l.grid[yy][xx] == c
			fmt.sbprintf(&b, `<path fill="%s" d="`, color(c))
			trace(&b, &mask)
			strings.write_string(&b, `"/>`)
		}
		strings.write_string(&b, "</g>\n")
	}
	all: Mask
	for l in layers {
		if !l.on do continue
		for y in 0 ..< H do for x in 0 ..< W do all[y][x] ||= l.grid[y][x] != '.'
	}
	fmt.sbprintf(&b, `<g id="silhouette" display="none"><path fill="%s" d="`, color('O'))
	trace(&b, &all)
	strings.write_string(&b, "\"/></g>\n</svg>\n")
	return strings.to_string(b)
}

Mask :: [H][W]bool

// Writes the outline of the mask's pixels as path data: one closed loop per
// boundary, the pixels on its right (clockwise on screen), so holes wind the
// other way and fill as holes under either fill rule. Straight runs are
// single segments; pixels touching only at a corner stay apart.
trace :: proc(b: ^strings.Builder, m: ^Mask) {
	V :: (W + 1) * (H + 1)
	at :: proc(m: ^Mask, x, y: int) -> bool {return x >= 0 && y >= 0 && x < W && y < H && m[y][x]}
	// Boundary edges by start vertex (at most two: pixels touching at a corner).
	out: [V][2]i32
	n: [V]int
	add :: proc(out: ^[V][2]i32, n: ^[V]int, x0, y0, x1, y1: int) {
		v := y0 * (W + 1) + x0
		out[v][n[v]] = i32(y1 * (W + 1) + x1)
		n[v] += 1
	}
	for y in 0 ..< H do for x in 0 ..< W {
		if !m[y][x] do continue
		if !at(m, x, y - 1) do add(&out, &n, x, y, x + 1, y)
		if !at(m, x + 1, y) do add(&out, &n, x + 1, y, x + 1, y + 1)
		if !at(m, x, y + 1) do add(&out, &n, x + 1, y + 1, x, y + 1)
		if !at(m, x - 1, y) do add(&out, &n, x, y + 1, x, y)
	}
	xy :: proc(v: i32) -> [2]int {return {int(v) % (W + 1), int(v) / (W + 1)}}
	for start in 0 ..< V {
		for n[start] > 0 {
			// Walk the loop, writing a point where the direction changes.
			pts: [dynamic][2]int
			defer delete(pts)
			v := i32(start)
			dir: [2]int
			for {
				k := 0
				if n[v] == 2 {
					// At a corner touch, turn right: keep to the pixels on the right.
					right := [2]int{-dir.y, dir.x}
					for j in 0 ..< 2 {
						if len(pts) > 0 && xy(out[v][j]) - xy(v) == right do k = j
					}
				}
				next := out[v][k]
				out[v][k] = out[v][n[v] - 1]
				n[v] -= 1
				d := xy(next) - xy(v)
				if len(pts) == 0 || d != dir do append(&pts, xy(v))
				dir = d
				v = next
				if v == i32(start) do break
			}
			fmt.sbprintf(b, "M%d %d", pts[0].x, pts[0].y)
			for p, i in pts[1:] {
				prev := pts[i]
				if p.y == prev.y do fmt.sbprintf(b, "H%d", p.x)
				else do fmt.sbprintf(b, "V%d", p.y)
			}
			strings.write_byte(b, 'Z')
		}
	}
}

hex_byte :: proc(s: string) -> u8 {
	v: u8
	for c in transmute([]u8)s {
		v <<= 4
		switch c {
		case '0' ..= '9': v |= c - '0'
		case 'a' ..= 'f': v |= c - 'a' + 10
		}
	}
	return v
}

// The visible layers flattened, scaled by `scale` without smoothing.
png :: proc(path: string, layers: []Layer, scale: int) -> bool {
	size := W * scale
	pixels := make([]u8, size * size * 4)
	defer delete(pixels)
	for l in layers {
		if !l.on do continue
		for y in 0 ..< H do for x in 0 ..< W {
			c := l.grid[y][x]
			if c == '.' do continue
			hex := color(c)
			rgba := [4]u8{hex_byte(hex[1:3]), hex_byte(hex[3:5]), hex_byte(hex[5:7]), 255}
			for dy in 0 ..< scale do for dx in 0 ..< scale {
				i := ((y * scale + dy) * size + x * scale + dx) * 4
				pixels[i + 0], pixels[i + 1], pixels[i + 2], pixels[i + 3] = rgba[0], rgba[1], rgba[2], rgba[3]
			}
		}
	}
	return stbi.write_png(strings.clone_to_cstring(path, context.temp_allocator), i32(size), i32(size), 4, raw_data(pixels), i32(size * 4)) != 0
}

