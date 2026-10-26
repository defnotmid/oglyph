// Bakes oglyph's shaping (through ovg's text_layout) for the oglyph launch
// video: every typing state of the Arabic and Devanagari lines, the Latin
// line under each feature set and the proof lines, as glyph ids, clusters and positions, plus each glyph's outline as
// SVG path data, into one JSON file the video script reads.
//
//     odin run . -collection:deps=<dir with ovg and oglyph> -- out.json
package bake

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import vg "deps:ovg"

NASKH :: "/usr/share/fonts/noto/NotoNaskhArabic-Regular.ttf"
DEVA :: "/usr/share/fonts/noto/NotoSansDevanagari-Regular.ttf"
NOTO :: "/usr/share/fonts/noto/NotoSans-Regular.ttf"

ARABIC :: "السلام عليكم"
DEVA_WORDS :: [3]string{"हिंदी", "धर्म", "क्षमा"}
LATIN :: "Office ½ 2/3 0 Small Caps"

// A face to lay text out in: its own collection, so the family it is
// asked for by is the only face there is.
Face :: struct {
	key:   string,
	fonts: vg.Font_Collection,
	// Outlines by size (they are in pixels), then glyph: the output's
	// tables "<key>@<size>".
	paths: map[f32]map[vg.Glyph_Index]string,
}

face_open :: proc(key, file: string, variations: []vg.Font_Variation = nil) -> ^Face {
	data, err := os.read_entire_file(file, context.allocator)
	fmt.assertf(err == nil, "%s: %v", file, err)
	f := new(Face)
	f.key = key
	vg.font_collection_init(&f.fonts)
	n := vg.font_collection_add(&f.fonts, data, variations = variations)
	fmt.assertf(n > 0, "%s did not load", file)
	return f
}

// The family the face answers to (its name table's).
face_family :: proc(f: ^Face) -> string {
	return f.fonts.faces[len(f.fonts.faces) - 1].family
}

Out :: struct {
	b: strings.Builder,
}

// Lays `text` out at `size` from (0, 0) on the baseline and writes one
// state: glyphs [id, cluster, x, y] in visual order and the extent; the
// glyphs' outlines go to the face's table.
state :: proc(o: ^Out, f: ^Face, text: string, size: f32, features: []vg.Font_Feature = nil) {
	pieces_state(o, f, {{text = text, style = {size = size, features = features}}})
}

// The same for pieces of one face, each with its own size and features.
pieces_state :: proc(o: ^Out, f: ^Face, pieces: []vg.Text_Piece) {
	l: vg.Text_Layout
	vg.text_layout_init(&l, context.temp_allocator)
	text := strings.builder_make(context.temp_allocator)
	for &p in pieces {
		p.style.family, p.style.weight = face_family(f), 400
		strings.write_string(&text, p.text)
	}
	vg.text_layout(&f.fonts, pieces, {}, &l)
	text_s := strings.to_string(text)
	size := pieces[0].style.size
	if size not_in f.paths {
		f.paths[size] = make(map[vg.Glyph_Index]string)
	}
	table := &f.paths[size]
	fmt.assertf(len(l.missing) == 0, "%s: missing %v", f.key, l.missing)
	fmt.sbprintf(&o.b, `{{"face":"%s@%d","text":%q,"min":[%.3f,%.3f],"max":[%.3f,%.3f],"glyphs":[`, f.key, int(size), text_s, l.min.x, l.min.y, l.max.x, l.max.y)
	for run in l.runs {
		for g, k in l.glyphs[run.first:][:run.count] {
			i := run.first + k
			fmt.sbprintf(&o.b, `%s[%d,%d,%.4f,%.4f]`, i == 0 ? "" : ",", g.glyph, l.clusters[i], g.x, g.y)
			if g.glyph not_in table {
				table[g.glyph] = glyph_d(vg.text_layout_font(&l, run), g.glyph, run.em)
			}
		}
	}
	strings.write_string(&o.b, "]}")
}

// The glyph's outline from its origin, in pixels (y down), as path data.
glyph_d :: proc(font: ^vg.Font, g: vg.Glyph_Index, em: f32) -> string {
	p: vg.Path
	vg.path_init(&p, context.temp_allocator)
	vg.font_glyph_path(font, g, 0, 0, em, &p)
	b := strings.builder_make()
	c := 0
	for v in p.verbs {
		switch v {
		case .Move_To:
			fmt.sbprintf(&b, "M%.2f %.2f", p.coords[c].x, p.coords[c].y)
		case .Line_To:
			fmt.sbprintf(&b, "L%.2f %.2f", p.coords[c].x, p.coords[c].y)
		case .Bezier_To:
			fmt.sbprintf(&b, "C%.2f %.2f %.2f %.2f %.2f %.2f", p.coords[c].x, p.coords[c].y, p.coords[c + 1].x,
				p.coords[c + 1].y, p.coords[c + 2].x, p.coords[c + 2].y)
		case .Close:
			strings.write_string(&b, "Z")
		case .Solid, .Hole:
		}
		c += vg.verb_num_coords(v)
	}
	return strings.to_string(b)
}

// Every prefix of `text` by codepoint, the empty one first: what the line
// is after each keystroke.
typing :: proc(o: ^Out, f: ^Face, text: string, size: f32) {
	strings.write_string(&o.b, "[")
	i := 0
	for n := 0; ; n += 1 {
		if n > 0 {
			strings.write_string(&o.b, ",")
		}
		state(o, f, text[:i], size)
		if i >= len(text) {
			break
		}
		_, w := utf8.decode_rune_in_string(text[i:])
		i += w
	}
	strings.write_string(&o.b, "]")
}

paths :: proc(o: ^Out, f: ^Face, first: bool) {
	k := 0
	for size, table in f.paths {
		fmt.sbprintf(&o.b, `%s"%s@%d":{{"family":%q,"glyphs":{{`, first && k == 0 ? "" : ",", f.key, int(size), face_family(f))
		n := 0
		for id, d in table {
			fmt.sbprintf(&o.b, `%s"%d":%q`, n == 0 ? "" : ",", id, d)
			n += 1
		}
		strings.write_string(&o.b, "}}")
		k += 1
	}
}

main :: proc() {
	out_path := len(os.args) > 1 ? os.args[1] : "glyphs.json"
	naskh, deva, noto := face_open("naskh", NASKH), face_open("deva", DEVA), face_open("noto", NOTO)
	o: Out
	strings.builder_init(&o.b)
	strings.write_string(&o.b, `{"arabic":`)
	typing(&o, naskh, ARABIC, 150)
	strings.write_string(&o.b, `,"devanagari":[`)
	for w, i in DEVA_WORDS {
		if i > 0 {
			strings.write_string(&o.b, ",")
		}
		typing(&o, deva, w, 190)
	}
	// The Latin line with ligatures off, then liga, frac, zero and smcp
	// turned on one at a time (each keeps the ones before), each on its own
	// words: Noto Sans's frac makes every digit a numerator, so the 0 is
	// left out of it.
	strings.write_string(&o.b, `],"latin":[`)
	for step in 0 ..< 5 {
		if step > 0 {
			strings.write_string(&o.b, ",")
		}
		on :: proc(b: bool) -> u32 {return 1 if b else 0}
		pieces := [5]vg.Text_Piece {
			{text = "Office ", style = {size = 92, features = {{"liga", on(step >= 1)}}}},
			{text = "½ ", style = {size = 92}},
			{text = "2/3 ", style = {size = 92, features = {{"frac", on(step >= 2)}}}},
			{text = "0 ", style = {size = 92, features = {{"zero", on(step >= 3)}}}},
			{text = "Small Caps", style = {size = 92, features = {{"smcp", on(step >= 4)}}}},
		}
		pieces_state(&o, noto, pieces[:])
	}
	// The weight sweep isn't baked: the video draws Adwaita Sans's instances
	// live (onimite's `variations`, the font from demo/fetch.sh).
	// The proof lines, at the size they are compared at.
	strings.write_string(&o.b, `],"proof":[`)
	state(&o, naskh, ARABIC, 104)
	strings.write_string(&o.b, ",")
	state(&o, deva, "हिंदी धर्म क्षमा", 104)
	strings.write_string(&o.b, ",")
	proof_latin := [3]vg.Text_Piece {
		{text = "Office ", style = {size = 104}},
		{text = "2/3 ", style = {size = 104, features = {{"frac", 1}}}},
		{text = "0", style = {size = 104, features = {{"zero", 1}}}},
	}
	pieces_state(&o, noto, proof_latin[:])
	strings.write_string(&o.b, `],"paths":{`)
	paths(&o, naskh, true)
	paths(&o, deva, false)
	paths(&o, noto, false)
	strings.write_string(&o.b, "}}")
	fmt.assertf(os.write_entire_file(out_path, transmute([]u8)strings.to_string(o.b)) == nil, "write %s", out_path)
	fmt.println("wrote", out_path, len(o.b.buf), "bytes;", face_family(naskh), "/", face_family(deva), "/", face_family(noto))
}
