package font

import "core:math/rand"
import "core:os"
import "core:testing"

@(private = "file")
vera := #load("../assets/Vera.ttf")

// Every query the reader answers, over every glyph and a spread of code
// points: what a corrupt font must survive.
@(private = "file")
read_all :: proc(f: ^Face, o: ^Outline) {
	for g in 0 ..< min(f.glyph_count, 4096) {
		glyph_outline(f, Glyph(g), o)
		glyph_box(f, Glyph(g))
		glyph_empty(f, Glyph(g))
		h_metrics(f, Glyph(g))
		kern(f, Glyph(g), Glyph(g + 1))
	}
	for cp := 0; cp < 0x30000; cp += 7 {
		glyph_index(f, rune(cp))
	}
	runes := make([]rune, codepoints(f, nil))
	defer delete(runes)
	codepoints(f, runes)
	names := make([]string, min(f.glyph_count, 4096))
	defer delete(names)
	glyph_names(f, names)
	for id in ([?]u16{1, 2, 4, 6, 16, 17, 256}) do delete(name_string(f, id))
}

@(test)
test_vera :: proc(t: ^testing.T) {
	f, err := load(vera)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, f.units_per_em, 2048)
	g := glyph_index(&f, 'A')
	testing.expect(t, g != 0)
	o: Outline
	defer outline_destroy(&o)
	testing.expect(t, glyph_outline(&f, g, &o))
	testing.expect_value(t, o.verbs[0], Verb.Move)
	testing.expect(t, glyph_empty(&f, glyph_index(&f, ' ')))
	testing.expect(t, kern(&f, glyph_index(&f, 'A'), glyph_index(&f, 'V')) < 0)
	// The characters it maps (fontTools: 256, from U+20 to U+FB02),
	// ascending, each to a glyph.
	runes := make([]rune, codepoints(&f, nil))
	defer delete(runes)
	testing.expect_value(t, codepoints(&f, runes), 256)
	testing.expect_value(t, runes[0], ' ')
	testing.expect_value(t, runes[255], 0xFB02)
	for r, i in runes {
		testing.expect(t, glyph_index(&f, r) != 0 && (i == 0 || r > runes[i - 1]))
	}
	// Its names are Macintosh records only (fontTools: the same strings).
	for want, id in ([?]string{1 = "Bitstream Vera Sans", 2 = "Roman", 6 = "BitstreamVeraSans-Roman"}) {
		if want == "" do continue
		s := name_string(&f, u16(id))
		testing.expect_value(t, s, want)
		delete(s)
	}
	testing.expect_value(t, name_string(&f, 300), "")
}

// fvar's axis and named instance names, from Windows records (fontTools:
// opsz "Optical size", wght "Weight", instance 6 "Bold" at wght 700).
// Skips without Adwaita Sans installed.
@(test)
test_names_variable :: proc(t: ^testing.T) {
	data, err := os.read_entire_file("/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf", context.allocator)
	if err != nil do return
	defer delete(data)
	f, _ := load(data)
	for want, i in ([?]string{"Optical size", "Weight"}) {
		a, ok := axis(&f, i)
		testing.expect(t, ok)
		s := name_string(&f, a.name_id)
		testing.expect_value(t, s, want)
		delete(s)
	}
	values: [2]f32
	id, ok := instance(&f, 6, values[:])
	testing.expect(t, ok)
	testing.expect_value(t, values[1], 700)
	s := name_string(&f, id)
	testing.expect_value(t, s, "Bold")
	delete(s)
	s = name_string(&f, 1)
	testing.expect_value(t, s, "Adwaita Sans")
	delete(s)
}

@(test)
test_not_fonts :: proc(t: ^testing.T) {
	_, err := load(nil)
	testing.expect_value(t, err, Error.Not_A_Font)
	_, err = load(transmute([]u8)string("ttcf\x00\x01\x00\x00\x00\x00\x00\x00"))
	testing.expect_value(t, err, Error.No_Face)
	_, err = load(vera, 1)
	testing.expect_value(t, err, Error.No_Face)
}

// Truncated and corrupted copies of a font load with an error or read
// without going out of bounds (an out-of-bounds index panics the test).
@(test)
test_corrupt :: proc(t: ^testing.T) {
	o: Outline
	defer outline_destroy(&o)
	for size := 0; size < len(vera); size += 997 {
		if f, err := load(vera[:size]); err == nil {
			read_all(&f, &o)
		}
	}
	data := make([]u8, len(vera))
	defer delete(data)
	r := rand.create(1)
	for _ in 0 ..< 200 {
		copy(data, vera)
		for _ in 0 ..< 1 + rand.int_max(64, rand.default_random_generator(&r)) {
			data[rand.int_max(len(data), rand.default_random_generator(&r))] = u8(rand.uint32(rand.default_random_generator(&r)))
		}
		if f, err := load(data); err == nil {
			read_all(&f, &o)
		}
	}
}
