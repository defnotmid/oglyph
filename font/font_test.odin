package font

import "core:math/rand"
import "core:os"
import "core:testing"

@(private = "file")
vera := #load("../assets/Vera.ttf")

@(private = "file")
tiny_cff := #load("../assets/TinyCFF.otf")

// Every query the reader answers, over every glyph and a spread of code
// points: what a corrupt font must survive.
@(private = "file")
read_all :: proc(f: ^Face, o: ^Outline) {
	for g in 0 ..< min(f.glyph_count, 4096) {
		glyph_outline(f, Glyph(g), o)
		glyph_box(f, Glyph(g))
		glyph_empty(f, Glyph(g))
		h_metrics(f, Glyph(g))
	}
	for cp := -7; cp < 0x30000; cp += 7 {
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

@(test)
test_edge_cases :: proc(t: ^testing.T) {
	// Partial u32 reads past either end of a slice return 0.
	bytes := [4]u8{1, 2, 3, 4}
	testing.expect_value(t, read_u32(bytes[:], -2), 0)
	testing.expect_value(t, read_u32(bytes[:], 2), 0)
	testing.expect_value(t, read_u32(bytes[:], 0), 0x01020304)

	// Negative runes map to glyph 0 in every cmap format.
	table := [1]u8{42}
	for fmt in ([?]u16{0, 4, 6, 12, 13}) {
		f := Face{cmap = {format = fmt, bytes = table[:]}}
		testing.expect_value(t, glyph_index(&f, -1), 0)
	}

	// A negative CFF DICT offset reads as past the table: a charset there
	// names nothing.
	for dict in ([?][]u8{{28, 0xff, 0xff, 15}, {251, 0, 15}, {29, 0xff, 0xff, 0xff, 0xff, 15}}) {
		charset: [1]int
		dict_ints(dict, 15, charset[:])
		c := Cff{table = table[:], charset = charset[0]}
		names: [2]string
		cff_glyph_names(&c, names[:])
		testing.expect_value(t, names[0], ".notdef")
		testing.expect_value(t, names[1], "")
	}

	// A 1-point off-curve contour does not swallow the next contour's start.
	o: Outline
	defer outline_destroy(&o)
	append(&o.glyf, Glyf_Point{flags = {}, x = 10, y = 20})
	append(&o.glyf, Glyf_Point{flags = {.On_Curve}, x = 30, y = 40})
	append(&o.glyf, Glyf_Point{flags = {.On_Curve}, x = 50, y = 60})
	append(&o.ends, 0, 2)
	testing.expect(t, glyf_contours(&o))
	moves := 0
	for v in o.verbs {
		if v == .Move do moves += 1
	}
	testing.expect_value(t, moves, 2)
}

// A cmap subtable in a format not read here gives way to the next most
// preferred; a face with no other has no usable cmap.
@(test)
test_cmap_unsupported :: proc(t: ^testing.T) {
	want, _ := load(vera)
	cmap := want.tables[.cmap].at
	// The font and a format 10 subtable after it.
	data := make([]u8, len(vera) + 2)
	defer delete(data)
	copy(data, vera)
	data[len(vera) + 1] = 10
	at := len(vera) - cmap
	point := proc(data: []u8, rec, at: int) {
		data[rec + 1], data[rec + 3] = 3, 10
		data[rec], data[rec + 2] = 0, 0
		data[rec + 4], data[rec + 5], data[rec + 6], data[rec + 7] = u8(at >> 24), u8(at >> 16), u8(at >> 8), u8(at)
	}
	point(data, cmap + 4, at)
	f, err := load(data)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, glyph_index(&f, 'A') != 0)
	testing.expect_value(t, glyph_index(&f, 'A'), glyph_index(&want, 'A'))
	for i in 0 ..< int(read_u16(data, cmap + 2)) {
		point(data, cmap + 4 + 8 * i, at)
	}
	_, err = load(data)
	testing.expect_value(t, err, Error.Bad_Table)
}

// A Unicode name record is read as UTF-16; an empty one gives way to the
// Macintosh record.
@(test)
test_name_unicode :: proc(t: ^testing.T) {
	// A pad (a table at 0 is none), the header, a Platform 0 record, a
	// Macintosh record, their strings.
	bytes := [?]u8 {
		0,
		0, 0, 0, 2, 0, 30,
		0, 0, 0, 3, 0, 0, 0, 1, 0, 2, 0, 0,
		0, 1, 0, 0, 0, 0, 0, 1, 0, 3, 0, 2,
		0, 'U', 'M', 'a', 'c',
	}
	f := Face{data = bytes[:]}
	f.tables[.name] = {1, len(bytes) - 1}
	s := name_string(&f, 1)
	testing.expect_value(t, s, "U")
	delete(s)
	bytes[16] = 0 // the Platform 0 record's length
	s = name_string(&f, 1)
	testing.expect_value(t, s, "Mac")
	delete(s)
}

// Truncated and corrupted copies of a font load with an error or read
// without going out of bounds (an out-of-bounds index panics the test).
@(test)
test_corrupt :: proc(t: ^testing.T) {
	o: Outline
	defer outline_destroy(&o)
	r := rand.create(1)
	for font in ([?][]u8{vera, tiny_cff}) {
		for size := 0; size < len(font); size += len(font) / 64 + 1 {
			if f, err := load(font[:size]); err == nil {
				read_all(&f, &o)
			}
		}
		data := make([]u8, len(font))
		defer delete(data)
		for _ in 0 ..< 200 {
			copy(data, font)
			for _ in 0 ..< 1 + rand.int_max(64, rand.default_random_generator(&r)) {
				data[rand.int_max(len(data), rand.default_random_generator(&r))] = u8(rand.uint32(rand.default_random_generator(&r)))
			}
			if f, err := load(data); err == nil {
				read_all(&f, &o)
			}
		}
	}
}
