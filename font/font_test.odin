package font

import "core:math/rand"
import "core:os"
import "core:slice"
import "core:testing"

@(private = "file")
vera := #load("../assets/Vera.ttf")

@(private = "file")
tiny_cff := #load("../assets/TinyCFF.otf")

// Noto Sans CJK JP's glyphs for A, 字, 永 and あ, subset (fontTools): a
// CID-keyed CFF with four font dicts, its top FontMatrix [1 0 0 1 0 0] and
// each font dict's [0.001 0 0 0.001 0 0], but [0.0005 0 0 0.0005 0 0] for
// A's.
@(private = "file")
tiny_cid := #load("../assets/TinyCID.otf")

// Generated (fontTools): A, acute, and Aacute as a seac of them with the
// accent at (150, 50), its own Encoding giving them codes 0x41, 0xAB and
// 0xC1.
@(private = "file")
tiny_seac := #load("../assets/TinySeac.otf")

// Generated (fontTools' charstring compiler and eexec cipher), a PFB: A,
// acute, Aacute as a seac of them (asb 50, adx 170, ady 30), "flexed" (a
// flex through the standard Subrs 0 to 2 with hmoveto and vmoveto in it,
// hint replacement through OtherSubr 3, and div), "sbw" (placed by sbw),
// and an Encoding of its own.
@(private = "file")
tiny_type1 := #load("../assets/TinyType1.pfb")

// The font's CFF table, as PDF embeds it.
@(private = "file")
cff_table :: proc(font: []u8) -> []u8 {
	f, _ := load(font)
	t := f.tables[.CFF]
	return font[t.at:][:t.size]
}

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
	cids := make([]u16, len(names))
	defer delete(cids)
	glyph_cids(f, cids)
	codes: [256]Glyph
	builtin_encoding(f, codes[:])
	for g in 0 ..< len(names) do glyph_matrix(f, Glyph(g))
	for pe in ([?][2]u16{{3, 0}, {1, 0}, {3, 1}}) {
		if c, ok := cmap_subtable(f, pe[0], pe[1]); ok {
			for cp := 0; cp < 0x10000; cp += 7 do cmap_glyph(f, &c, rune(cp))
		}
	}
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
	for font in ([?][]u8{vera, tiny_cff, tiny_cid, tiny_seac, cff_table(tiny_cid), cff_table(tiny_seac)}) {
		for size := 0; size < len(font); size += len(font) / 64 + 1 {
			if f, err := load(font[:size]); err == nil {
				read_all(&f, &o)
			}
			if f, err := load(font[:size], need_cmap = false); err == nil {
				read_all(&f, &o)
			}
			if f, err := load_cff(font[:size]); err == nil {
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
			if f, err := load_cff(data); err == nil {
				read_all(&f, &o)
			}
		}
	}
	// Type 1: as a PFB, and as PDF's FontFile (its cleartext and binary
	// eexec part), cut short and corrupted.
	pdf := type1_fontfile(tiny_type1, false)
	defer delete(pdf)
	for font in ([?][]u8{tiny_type1, pdf}) {
		for size := 0; size < len(font); size += 7 {
			if f, err := load_type1(font[:size]); err == nil {
				read_all(&f, &o)
				face_destroy(&f)
			}
		}
		data := make([]u8, len(font))
		defer delete(data)
		for _ in 0 ..< 300 {
			copy(data, font)
			for _ in 0 ..< 1 + rand.int_max(16, rand.default_random_generator(&r)) {
				data[rand.int_max(len(data), rand.default_random_generator(&r))] = u8(rand.uint32(rand.default_random_generator(&r)))
			}
			if f, err := load_type1(data); err == nil {
				read_all(&f, &o)
				face_destroy(&f)
			}
		}
	}
}

// A PFB's segments as PDF's FontFile holds them: the cleartext, then the
// eexec part in binary or (`hex`) as hexadecimal lines.
@(private = "file")
type1_fontfile :: proc(pfb: []u8, hex: bool) -> []u8 {
	out: [dynamic]u8
	for at := 0; at + 6 <= len(pfb) && pfb[at] == 0x80 && pfb[at + 1] != 3; {
		size := int(pfb[at + 2]) | int(pfb[at + 3]) << 8 | int(pfb[at + 4]) << 16 | int(pfb[at + 5]) << 24
		seg := pfb[at + 6:][:size]
		at += 6 + size
		if pfb[at - 6 - size + 1] == 1 {
			append(&out, ..seg)
			continue
		}
		digits := "0123456789abcdef"
		for c, i in seg {
			if !hex {
				append(&out, c)
				continue
			}
			append(&out, digits[c >> 4], digits[c & 0xf])
			if i % 32 == 31 do append(&out, '\n')
		}
	}
	return out[:]
}

// A CFF table read alone (PDF's FontFile3) gives the outlines it gives in
// its OpenType font; only the font's other tables are missing.
@(test)
test_bare_cff :: proc(t: ^testing.T) {
	a, b: Outline
	defer outline_destroy(&a)
	defer outline_destroy(&b)
	for font in ([?][]u8{tiny_cff, tiny_cid, tiny_seac}) {
		f, err := load(font)
		testing.expect_value(t, err, Error.None)
		bare: Face
		bare, err = load_cff(cff_table(font))
		testing.expect_value(t, err, Error.None)
		testing.expect_value(t, bare.glyph_count, f.glyph_count)
		testing.expect_value(t, bare.units_per_em, 1000)
		for g in 0 ..< f.glyph_count {
			testing.expect_value(t, glyph_outline(&bare, Glyph(g), &b), glyph_outline(&f, Glyph(g), &a))
			testing.expect(t, slice.equal(a.verbs[:], b.verbs[:]) && slice.equal(a.points[:], b.points[:]))
			testing.expect_value(t, glyph_matrix(&bare, Glyph(g)), glyph_matrix(&f, Glyph(g)))
		}
		testing.expect(t, glyph_outline(&bare, 1, &b))
		// The charstrings' widths (fontTools' T2WidthExtractor), and in
		// TinyCID, a real font, hmtx's advances and side bearings (one
		// width is in a subroutine).
		for g in 0 ..< f.glyph_count {
			advance, lsb := h_metrics(&bare, Glyph(g))
			want_advance, want_lsb := h_metrics(&f, Glyph(g))
			if raw_data(font) == raw_data(tiny_cff) {
				widths := [4]int{400, 500, 600, 0}
				want_advance = widths[g]
			} else if raw_data(font) == raw_data(tiny_seac) {
				want_advance, want_lsb = 600, lsb
			}
			testing.expectf(t, advance == want_advance && lsb == want_lsb, "glyph %d: %d %d, want %d %d", g, advance, lsb, want_advance, want_lsb)
		}
		testing.expect_value(t, glyph_index(&bare, 'A'), 0)
	}
	_, err := load_cff(vera)
	testing.expect_value(t, err, Error.Not_A_Font)
	_, err = load_cff(nil)
	testing.expect_value(t, err, Error.Not_A_Font)
}

// A CID-keyed font's CIDs (fontTools: cid00034, cid01461, cid15364,
// cid23015 after .notdef) and FontMatrix, the top dict's after the glyph's
// font dict's.
@(test)
test_cid_keyed :: proc(t: ^testing.T) {
	f, err := load_cff(cff_table(tiny_cid))
	testing.expect_value(t, err, Error.None)
	cids: [6]u16
	testing.expect(t, glyph_cids(&f, cids[:]))
	testing.expect_value(t, cids, [6]u16{0, 34, 1461, 15364, 23015, 0})
	names: [5]string
	glyph_names(&f, names[:])
	testing.expect_value(t, names[1], "")
	testing.expect_value(t, glyph_matrix(&f, 1), matrix[2, 3]f32{0.0005, 0, 0, 0, 0.0005, 0})
	testing.expect_value(t, glyph_matrix(&f, 2), matrix[2, 3]f32{0.001, 0, 0, 0, 0.001, 0})
	// A top dict without a FontMatrix: the font dict's applies alone (a
	// font dict [0.001 0 0 0.001 0 0], one font dict for every glyph).
	{
		// A real 0.001 ("1E-3": nibbles 1, E-, 3, end), 0, 0, 0.001, 0, 0,
		// FontMatrix; an INDEX of that dict; FDSelect format 0.
		dict := [?]u8{30, 0x1c, 0x3f, 139, 139, 30, 0x1c, 0x3f, 139, 139, 12, 7}
		index: [5 + len(dict)]u8
		index[1], index[2], index[3], index[4] = 1, 1, 1, 1 + len(dict)
		copy(index[5:], dict[:])
		fdselect := [3]u8{0, 0, 0}
		g := Face{cff = {table = index[:], fontdicts = index[:], fdselect = fdselect[:], font_matrix = {0.001, 0, 0, 0, 0.001, 0}}}
		testing.expect_value(t, glyph_matrix(&g, 1), matrix[2, 3]f32{0.001, 0, 0, 0, 0.001, 0})
		// A top dict giving one: it applies after the font dict's.
		g.cff.top_matrix = true
		g.cff.font_matrix = {2, 0, 0, 0, 2, 0}
		testing.expect_value(t, glyph_matrix(&g, 1), matrix[2, 3]f32{0.002, 0, 0, 0, 0.002, 0})
	}
	// A face that isn't CID-keyed has no CIDs.
	f, _ = load(tiny_cff)
	testing.expect(t, !glyph_cids(&f, cids[:]))
	testing.expect_value(t, cids, [6]u16{})
	testing.expect_value(t, glyph_matrix(&f, 1), matrix[2, 3]f32{0.001, 0, 0, 0, 0.001, 0})
	f, _ = load(vera)
	testing.expect_value(t, glyph_matrix(&f, 1), matrix[2, 3]f32{1.0 / 2048, 0, 0, 0, 1.0 / 2048, 0})
}

// A seac glyph (endchar with a width and four operands) is its base glyph
// and its accent moved by (adx, ady).
@(test)
test_seac :: proc(t: ^testing.T) {
	f, _ := load(tiny_seac)
	base, accent, seac: Outline
	defer outline_destroy(&base)
	defer outline_destroy(&accent)
	defer outline_destroy(&seac)
	testing.expect(t, glyph_outline(&f, 1, &base))
	testing.expect(t, glyph_outline(&f, 2, &accent))
	testing.expect(t, glyph_outline(&f, 3, &seac))
	testing.expect_value(t, len(seac.verbs), len(base.verbs) + len(accent.verbs))
	testing.expect(t, slice.equal(seac.verbs[:len(base.verbs)], base.verbs[:]) && slice.equal(seac.verbs[len(base.verbs):], accent.verbs[:]))
	testing.expect_value(t, len(seac.points), len(base.points) + len(accent.points))
	testing.expect(t, slice.equal(seac.points[:len(base.points)], base.points[:]))
	for p, i in accent.points {
		testing.expect_value(t, seac.points[len(base.points) + i], p + {150, 50})
	}
	x0, y0, x1, y1, ok := glyph_box(&f, 3)
	testing.expect(t, ok)
	testing.expect_value(t, [4]int{x0, y0, x1, y1}, [4]int{0, 0, 600, 950})
}

// A TrueType font that maps no Unicode loads when asked to, addressed by
// glyph id, and its other cmap subtables map codes: Mac Roman (1, 0), and
// (3, 0) once Vera's (3, 1) is relabelled symbolic.
@(test)
test_no_unicode_cmap :: proc(t: ^testing.T) {
	want, _ := load(vera)
	a, b: Outline
	defer outline_destroy(&a)
	defer outline_destroy(&b)
	mac, ok := cmap_subtable(&want, 1, 0)
	testing.expect(t, ok)
	testing.expect_value(t, cmap_glyph(&want, &mac, 'A'), glyph_index(&want, 'A'))
	testing.expect_value(t, cmap_glyph(&want, &mac, 0x8e), glyph_index(&want, 0xe9)) // é
	_, ok = cmap_subtable(&want, 3, 0)
	testing.expect(t, !ok)

	data := make([]u8, len(vera))
	defer delete(data)
	copy(data, vera)
	cmap := want.tables[.cmap].at
	for i in 0 ..< int(read_u16(data, cmap + 2)) {
		if rec := cmap + 4 + 8 * i; read_u16(data, rec) == 3 {
			data[rec + 3] = 0
		}
	}
	_, err := load(data)
	testing.expect_value(t, err, Error.Bad_Table)
	f: Face
	f, err = load(data, need_cmap = false)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, glyph_index(&f, 'A'), 0)
	symbol: Cmap
	symbol, ok = cmap_subtable(&f, 3, 0)
	testing.expect(t, ok)
	testing.expect_value(t, cmap_glyph(&f, &symbol, 'A'), glyph_index(&want, 'A'))

	// No cmap at all.
	copy(data, vera)
	for i in 0 ..< int(read_u16(data, 4)) {
		if rec := 12 + 16 * i; tag_is(data, rec, "cmap") {
			data[rec] = 'x'
		}
	}
	_, err = load(data)
	testing.expect_value(t, err, Error.Missing_Table)
	f, err = load(data, need_cmap = false)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, glyph_index(&f, 'A'), 0)
	_, ok = cmap_subtable(&f, 1, 0)
	testing.expect(t, !ok)
	for g in 0 ..< f.glyph_count {
		testing.expect_value(t, glyph_outline(&f, Glyph(g), &b), glyph_outline(&want, Glyph(g), &a))
		testing.expect(t, slice.equal(a.points[:], b.points[:]))
	}
}

// A CFF font's built-in Encoding: Standard (TinyCFF), its own (TinySeac),
// none in a CID-keyed or TrueType font; ranges of codes with supplements,
// and Expert, over a custom charset.
@(test)
test_builtin_encoding :: proc(t: ^testing.T) {
	codes: [256]Glyph
	want: [256]Glyph
	f, _ := load(tiny_cff) // .notdef, B, A, space
	testing.expect(t, builtin_encoding(&f, codes[:]))
	want[' '], want['A'], want['B'] = 3, 2, 1
	testing.expect_value(t, codes, want)
	f, _ = load_cff(cff_table(tiny_seac))
	testing.expect(t, builtin_encoding(&f, codes[:]))
	want = {}
	want[0x41], want[0xab], want[0xc1] = 1, 2, 3
	testing.expect_value(t, codes, want)
	for font in ([?][]u8{tiny_cid, vera}) {
		f, _ = load(font)
		testing.expect(t, !builtin_encoding(&f, codes[:]))
		testing.expect_value(t, codes, [256]Glyph{})
	}

	// Three pad bytes; a charset at 3 naming glyphs 1 to 3 A (SID 34),
	// exclamsmall (229) and space (1); an Encoding at 10 giving them codes
	// 0x61 to 0x63 in a range, then supplements: 0x41 for A, 0x20 for space.
	bytes := [?]u8{0, 0, 0, 0, 0, 34, 0, 229, 0, 1, 0x81, 1, 0x61, 2, 2, 0x41, 0, 34, 0x20, 0, 1}
	count := [2]u8{0, 4}
	g := Face{cff = {table = bytes[:], charstrings = count[:], charset = 3, encoding = 10}}
	testing.expect(t, builtin_encoding(&g, codes[:]))
	want = {}
	want[0x61], want[0x62], want[0x63], want[0x41], want[0x20] = 1, 2, 3, 1, 3
	testing.expect_value(t, codes, want)
	// Expert Encoding: space is 0x20, exclamsmall 0x21; A has no code.
	g.cff.encoding = 1
	testing.expect(t, builtin_encoding(&g, codes[:]))
	want = {}
	want[0x20], want[0x21] = 3, 2
	testing.expect_value(t, codes, want)
	// A short `out` takes the codes below its length.
	short: [0x21]Glyph
	testing.expect(t, builtin_encoding(&g, short[:]))
	testing.expect_value(t, short[0x20], 3)
}

// Glyph names to characters by the Adobe Glyph List's rules (fontTools'
// agl.toUnicode agrees on every AGL and installed font's glyph name).
@(test)
test_glyph_name_runes :: proc(t: ^testing.T) {
	Case :: struct {
		name: string,
		zapf: bool,
		want: []rune,
	}
	cases := [?]Case {
		{"Aacute", false, {0xc1}},
		{"dalethatafpatah", false, {0x5d3, 0x5b2}},
		{"f_f_i.alt", false, {'f', 'f', 'i'}},
		{"uni20AC0308", false, {0x20ac, 0x308}},
		{"uni20ac", false, {}},
		{"uniD800", false, {}},
		{"u1F600.sc", false, {0x1f600}},
		{"u110000", false, {}},
		{"a1", false, {}},
		{"a1", true, {0x2701}},
		{"A_a1", true, {'A', 0x2701}},
		{".notdef", false, {}},
		{"", false, {}},
	}
	out: [4]rune
	for c in cases {
		n := glyph_name_runes(c.name, out[:], c.zapf)
		testing.expectf(t, n == len(c.want) && slice.equal(out[:n], c.want), "%s: %v", c.name, out[:n])
	}
	// nil counts; a short out takes what reaches.
	testing.expect_value(t, glyph_name_runes("f_f_i", nil), 3)
	testing.expect_value(t, glyph_name_runes("f_f_i", out[:1]), 3)
	testing.expect_value(t, out[0], 'f')
}

// A Type 1 font (fontTools draws the same, but for sbw, which it skips):
// read as a PFB, as PDF's FontFile in binary and in hexadecimal.
@(test)
test_type1 :: proc(t: ^testing.T) {
	pdf, hex := type1_fontfile(tiny_type1, false), type1_fontfile(tiny_type1, true)
	defer delete(pdf)
	defer delete(hex)
	o: Outline
	defer outline_destroy(&o)
	for font in ([?][]u8{tiny_type1, pdf, hex}) {
		f, err := load_type1(font)
		defer face_destroy(&f)
		testing.expect_value(t, err, Error.None)
		testing.expect_value(t, f.glyph_count, 6)
		testing.expect_value(t, f.units_per_em, 1000)
		testing.expect_value(t, glyph_matrix(&f, 1), matrix[2, 3]f32{0.001, 0, 0, 0, 0.001, 0})
		names: [6]string
		glyph_names(&f, names[:])
		testing.expect_value(t, names, [6]string{".notdef", "A", "acute", "Aacute", "flexed", "sbw"})
		codes, want_codes: [256]Glyph
		testing.expect(t, builtin_encoding(&f, codes[:]))
		want_codes['A'], want_codes[0xab], want_codes[0xc1], want_codes['f'], want_codes['s'] = 1, 2, 3, 4, 5
		testing.expect_value(t, codes, want_codes)
		testing.expect(t, !glyph_outline(&f, 0, &o))
		Case :: struct {
			g:      Glyph,
			verbs:  []Verb,
			points: [][2]f32,
		}
		cases := [?]Case {
			{1, {.Move, .Line, .Line, .Line}, {{20, 0}, {320, 700}, {620, 0}, {20, 0}}},
			{3, {.Move, .Line, .Line, .Line, .Move, .Line, .Line, .Line, .Line}, {{20, 0}, {320, 700}, {620, 0}, {20, 0}, {240, 780}, {340, 780}, {340, 930}, {240, 930}, {240, 780}}},
			{4, {.Move, .Cubic, .Cubic, .Line}, {{100, 0}, {150, 30}, {170, 30}, {200, 30}, {230, 30}, {250, 30}, {250, 0}, {100, 0}}},
			{5, {.Move, .Line, .Line, .Line}, {{30, 40}, {130, 40}, {130, 140}, {30, 40}}},
		}
		for c in cases {
			testing.expect(t, glyph_outline(&f, c.g, &o))
			testing.expectf(t, slice.equal(o.verbs[:], c.verbs) && slice.equal(o.points[:], c.points), "glyph %d: %v %v", c.g, o.verbs, o.points)
		}
		x0, y0, x1, y1, ok := glyph_box(&f, 3)
		testing.expect(t, ok)
		testing.expect_value(t, [4]int{x0, y0, x1, y1}, [4]int{20, 0, 620, 930})
		// hsbw's and sbw's widths and side bearings.
		for want in ([?][3]int{{1, 600, 20}, {2, 300, 50}, {5, 600, 30}}) {
			advance, lsb := h_metrics(&f, Glyph(want[0]))
			testing.expect_value(t, [2]int{advance, lsb}, [2]int{want[1], want[2]})
		}
	}
	_, err := load_type1(vera)
	testing.expect_value(t, err, Error.Not_A_Font)
	_, err = load_type1(nil)
	testing.expect_value(t, err, Error.Not_A_Font)
}
