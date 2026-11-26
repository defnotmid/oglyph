// Reads TrueType and OpenType fonts: a face's tables, the character to
// glyph map, metrics, glyph outlines and variable fonts' instances
// (kerning is oglyph/shape's: GPOS and the kern table). Core only: anything that draws glyphs can use it (ovg's text
// does), and oglyph/shape shapes with it.
//
// `load` reads a face once: where each table it uses lies and the header
// facts (units per em, the metrics counts, the cmap subtable, CFF's
// indexes), so a lookup reads the font's own bytes with no further setup.
// Every read is bounds-checked: past the end of the data it gives 0, so a
// corrupt or truncated font gives wrong glyphs, never a read out of
// bounds, and `load` rejects a face whose required tables are missing.
// For PDF's embedded fonts, `load_cff` reads a bare CFF font program,
// `load_type1` a Type 1 font, and `load` can take a TrueType subset that
// maps no Unicode characters, all addressed by glyph id (`glyph_cids`,
// `cmap_subtable`, `builtin_encoding`, `glyph_names`, `glyph_name_runes`
// and `glyph_matrix` give the rest).
//
// Outlines (`glyph_outline`) are TrueType's quadratic contours (glyf, with
// composite glyphs) or CFF's Type 2 charstrings (cubic), in font units, y
// up.
package font

import "core:math"
import "core:slice"

Error :: enum u8 {
	None,
	// Neither a font nor a collection.
	Not_A_Font,
	// The collection has no face at that index.
	No_Face,
	// cmap, head, hhea or hmtx is missing, or all of glyf (with loca), CFF
	// and CFF2.
	Missing_Table,
	// No cmap subtable maps Unicode (unless `load`'s need_cmap is false),
	// or a table's header is cut short.
	Bad_Table,
	// CFF other than version 1 with Type 2 charstrings (or CFF2).
	Unsupported,
}

// The tables read.
Table :: enum u8 {
	cmap,
	head,
	hhea,
	hmtx,
	maxp,
	loca,
	glyf,
	CFF,
	GPOS,
	GSUB,
	COLR,
	CPAL,
	sbix,
	CBDT,
	name,
	OS2,
	post,
	fvar,
	avar,
	gvar,
	HVAR,
	CFF2,
}

@(private)
TAGS := [Table]string {
	.cmap = "cmap",
	.head = "head",
	.hhea = "hhea",
	.hmtx = "hmtx",
	.maxp = "maxp",
	.loca = "loca",
	.glyf = "glyf",
	.CFF  = "CFF ",
	.GPOS = "GPOS",
	.GSUB = "GSUB",
	.COLR = "COLR",
	.CPAL = "CPAL",
	.sbix = "sbix",
	.CBDT = "CBDT",
	.name = "name",
	.OS2  = "OS/2",
	.post = "post",
	.fvar = "fvar",
	.avar = "avar",
	.gvar = "gvar",
	.HVAR = "HVAR",
	.CFF2 = "CFF2",
}

// The cmap subtables (platform, encoding) that map Unicode, most preferred
// first: the full repertoire (Windows, then Unicode's), then the BMP.
// Unicode's encoding 5 (variation sequences) maps no characters alone.
@(private, rodata)
CMAP_PREFERENCE := [?][2]u16{{3, 10}, {0, 6}, {0, 4}, {3, 1}, {0, 3}, {0, 2}, {0, 1}, {0, 0}}

// Where a table lies in the data (`at` is 0 when the face has none).
Span :: struct {
	at, size: int,
}

Glyph :: u16

Face :: struct {
	// The font's bytes (borrowed; must outlive the face).
	data:                      []u8,
	// The face's table directory (non-zero in a collection).
	start:                     int,
	tables:                    [Table]Span,
	glyph_count:               int,
	units_per_em:              int,
	// hhea's.
	ascent, descent, line_gap: int,
	// hmtx: advance and left side bearing pairs, then the side bearings of
	// the glyphs past them (which take the last pair's advance).
	metrics:                   []Long_Metric,
	bearings:                  []I16,
	// Each glyph's glyf offset (and one past the last): 16-bit and halved,
	// or 32-bit; neither for an unknown format.
	loca_short:                []U16,
	loca_long:                 []U32,
	cmap:                      Cmap,
	cff:                       Cff,
	// A Type 1 font's (`load_type1`).
	t1:                        Type1,
	// A variable font's instance (var.odin): each axis's normalized
	// coordinate (2.14 fixed point; all 0 is the default instance).
	coords:                    [MAX_AXES]i16,
	axis_count:                int,
}

// The cmap subtable used: its format's arrays, slices of the data.
Cmap :: struct {
	format:    u16,
	// Where the subtable starts.
	at:        int,
	// Format 0: a glyph per code point below len.
	bytes:     []u8,
	// Format 4: segments, each a code point range (starts[i] ..= ends[i])
	// mapped by adding deltas[i], or by a glyph array ranges[i] bytes past
	// the entry's own place at ranges_at + 2 i.
	ends:      []U16,
	starts:    []U16,
	deltas:    []I16,
	ranges:    []U16,
	ranges_at: int,
	// Format 6: glyphs for first ..< first + len.
	first:     int,
	glyphs:    []U16,
	// Formats 12 and 13: code point ranges and their (first) glyph.
	groups:    []Group,
}

// OpenType's records as stored: big-endian and unaligned, so #packed.
U16 :: struct #packed {
	v: u16be,
}

I16 :: struct #packed {
	v: i16be,
}

U32 :: struct #packed {
	v: u32be,
}

Long_Metric :: struct #packed {
	advance: u16be,
	lsb:     i16be,
}

Group :: struct #packed {
	first, last, glyph: u32be,
}

// ---- reading ----------------------------------------------------------------------

// Big-endian reads, 0 past either end of the data.
read_u8 :: #force_inline proc "contextless" (d: []u8, at: int) -> u8 {
	if at < 0 || at >= len(d) {
		return 0
	}
	#no_bounds_check return d[at]
}

read_u16 :: #force_inline proc "contextless" (d: []u8, at: int) -> u16 {
	if at < 0 || at + 2 > len(d) {
		return 0
	}
	#no_bounds_check return u16(d[at]) << 8 | u16(d[at + 1])
}

read_i16 :: #force_inline proc "contextless" (d: []u8, at: int) -> i16 {
	return i16(read_u16(d, at))
}

read_u24 :: #force_inline proc "contextless" (d: []u8, at: int) -> u32 {
	if at < 0 || at + 3 > len(d) {
		return 0
	}
	#no_bounds_check return u32(d[at]) << 16 | u32(d[at + 1]) << 8 | u32(d[at + 2])
}

read_u32 :: #force_inline proc "contextless" (d: []u8, at: int) -> u32 {
	if at < 0 || at + 4 > len(d) {
		return 0
	}
	#no_bounds_check return u32(d[at]) << 24 | u32(d[at + 1]) << 16 | u32(d[at + 2]) << 8 | u32(d[at + 3])
}

// `count` records of type T at `at`; nil unless they all lie in the data.
@(private)
records :: proc "contextless" (d: []u8, at, count: int, $T: typeid) -> []T {
	if at < 0 || count < 0 || at + count * size_of(T) > len(d) {
		return nil
	}
	#no_bounds_check return slice.reinterpret([]T, d[at:][:count * size_of(T)])
}

// `count` records at `at`, or as many as lie in the data.
@(private)
records_clamped :: proc "contextless" (d: []u8, at, count: int, $T: typeid) -> []T {
	if at < 0 || at > len(d) {
		return nil
	}
	return records(d, at, min(count, (len(d) - at) / size_of(T)), T)
}

@(private)
tag_is :: proc "contextless" (d: []u8, at: int, tag: string) -> bool {
	return at >= 0 && at + 4 <= len(d) && string(d[at:at + 4]) == tag
}

// ---- faces ------------------------------------------------------------------------

// Where face `index` starts: 0 for a font file's only face, or the
// collection's (ttcf) offset for it.
face_offset :: proc(data: []u8, index: int) -> (start: int, err: Error) {
	if tag_is(data, 0, "\x00\x01\x00\x00") || tag_is(data, 0, "OTTO") || tag_is(data, 0, "true") || tag_is(data, 0, "1\x00\x00\x00") || tag_is(data, 0, "typ1") {
		return 0, nil if index == 0 else .No_Face
	}
	if !tag_is(data, 0, "ttcf") {
		return 0, .Not_A_Font
	}
	if v := read_u32(data, 4); v != 0x10000 && v != 0x20000 {
		return 0, .Not_A_Font
	}
	if index < 0 || index >= int(read_u32(data, 8)) {
		return 0, .No_Face
	}
	return int(read_u32(data, 12 + index * 4)), nil
}

// Faces in the file: 1 for a font, the count for a collection, 0 for
// neither.
face_count :: proc(data: []u8) -> int {
	if _, err := face_offset(data, 0); err == .Not_A_Font {
		return 0
	}
	if tag_is(data, 0, "ttcf") {
		return int(read_u32(data, 8))
	}
	return 1
}

// Reads face `index` of a font or collection. `need_cmap` false also takes
// a face that maps no Unicode characters (no cmap, or only symbolic or
// Macintosh subtables), as PDF embeds TrueType subsets: `glyph_index` then
// gives 0, and `cmap_subtable` reads the subtables it has.
load :: proc(data: []u8, index := 0, need_cmap := true) -> (f: Face, err: Error) {
	f.data = data
	f.start = face_offset(data, index) or_return
	for i in 0 ..< int(read_u16(data, f.start + 4)) {
		rec := f.start + 12 + i * 16
		at, size := int(read_u32(data, rec + 8)), int(read_u32(data, rec + 12))
		if at == 0 || at >= len(data) {
			continue
		}
		for tag, t in TAGS {
			if f.tables[t].at == 0 && tag_is(data, rec, tag) {
				f.tables[t] = {at, min(size, len(data) - at)}
			}
		}
	}
	t := &f.tables
	if (need_cmap && t[.cmap].at == 0) || t[.head].at == 0 || t[.hhea].at == 0 || t[.hmtx].at == 0 {
		return {}, .Missing_Table
	}
	if t[.head].size < 54 || t[.hhea].size < 36 {
		return {}, .Bad_Table
	}
	if t[.glyf].at != 0 {
		if t[.loca].at == 0 {
			return {}, .Missing_Table
		}
	} else if t[.CFF2].at != 0 {
		cff2_load(&f) or_return
	} else if t[.CFF].at == 0 {
		return {}, .Missing_Table
	} else {
		cff_load(&f, data[t[.CFF].at:][:t[.CFF].size]) or_return
	}
	f.glyph_count = int(read_u16(data, t[.maxp].at + 4)) if t[.maxp].at != 0 else 0xffff
	if fvar := t[.fvar].at; fvar != 0 && read_u16(data, fvar) == 1 {
		if n := int(read_u16(data, fvar + 8)); n <= MAX_AXES {
			f.axis_count = n
		}
	}
	head, hhea := t[.head].at, t[.hhea].at
	f.units_per_em = int(read_u16(data, head + 18))
	f.ascent = int(read_i16(data, hhea + 4))
	f.descent = int(read_i16(data, hhea + 6))
	f.line_gap = int(read_i16(data, hhea + 8))
	hmtx := t[.hmtx]
	hmtx_data := data[hmtx.at:][:hmtx.size]
	long := int(read_u16(data, hhea + 34))
	f.metrics = records_clamped(hmtx_data, 0, long, Long_Metric)
	f.bearings = records_clamped(hmtx_data, 4 * long, f.glyph_count - long, I16)
	if loca := t[.loca]; loca.at != 0 {
		switch read_u16(data, head + 50) {
		case 0:
			f.loca_short = records_clamped(data[loca.at:][:loca.size], 0, f.glyph_count + 1, U16)
		case 1:
			f.loca_long = records_clamped(data[loca.at:][:loca.size], 0, f.glyph_count + 1, U32)
		}
	}
	// The most preferred Unicode subtable the face has in a format read here.
	cmap := t[.cmap].at
	m, best := 0, len(CMAP_PREFERENCE)
	for i in 0 ..< (int(read_u16(data, cmap + 2)) if cmap != 0 else 0) {
		rec := cmap + 4 + 8 * i
		if k, found := slice.linear_search(CMAP_PREFERENCE[:], [2]u16{read_u16(data, rec), read_u16(data, rec + 2)}); found && k < best {
			at := cmap + int(read_u32(data, rec + 4))
			if cmap_format_read(read_u16(data, at)) {
				m, best = at, k
			}
		}
	}
	if m != 0 {
		f.cmap = cmap_read(data, m) or_return
	} else if need_cmap {
		return {}, .Bad_Table
	}
	return f, nil
}

// Reads a bare CFF font program (PDF's FontFile3 of subtype Type1C or
// CIDFontType0C): its glyphs, addressed by id, and their names or CIDs.
// It has no metrics (`h_metrics` gives 0, ascent, descent and line gap are
// 0: PDF gives the widths), no cmap, and units per em from its FontMatrix
// (`glyph_matrix`: 1000 unless it says otherwise).
load_cff :: proc(data: []u8) -> (f: Face, err: Error) {
	if read_u8(data, 0) != 1 || read_u8(data, 2) < 4 {
		return {}, .Not_A_Font
	}
	f.data = data
	cff_load(&f, data) or_return
	f.glyph_count = index_count(f.cff.charstrings)
	// A scale outside unitsPerEm's range (or NaN) counts as the default.
	f.units_per_em = 1000
	if s := abs(glyph_matrix(&f, 0)[0, 0]); s >= 1.0 / 0xffff && s <= 1 {
		f.units_per_em = int(math.round(1 / s))
	}
	return f, nil
}

// Maps glyph `g`'s outline (font units) to an em of 1: Type 1's or CFF's
// FontMatrix (a CID-keyed font's after the matrix of the glyph's font
// dict), else 1 / units per em. PDF's text space is this times the font size.
glyph_matrix :: proc(f: ^Face, g: Glyph) -> matrix[2, 3]f32 {
	if f.t1.program != nil {
		return f.t1.font_matrix
	}
	c := &f.cff
	if c.table == nil || c.cff2 {
		s := 1 / f32(max(f.units_per_em, 1))
		return {s, 0, 0, 0, s, 0}
	}
	m := c.font_matrix
	if c.fontdicts != nil {
		if fd, ok := font_matrix(index_get(c.fontdicts, glyph_fd(c, g))); ok {
			// The top dict's applies after the font dict's.
			m = affine_mul(m, fd)
		}
	}
	return m
}

// The cmap subtables read: formats 0, 4, 6, 12 and 13.
@(private)
cmap_format_read :: proc(format: u16) -> bool {
	switch format {
	case 0, 4, 6, 12, 13:
		return true
	}
	return false
}

// The subtable at `m`, as its format's arrays.
@(private)
cmap_read :: proc(data: []u8, m: int) -> (c: Cmap, err: Error) {
	c.at = m
	c.format = read_u16(data, m)
	switch c.format {
	case 0:
		c.bytes = records_clamped(data, m + 6, min(int(read_u16(data, m + 2)) - 6, 256), u8)
	case 4:
		segs := int(read_u16(data, m + 6)) / 2
		c.ends = records(data, m + 14, segs, U16)
		c.starts = records(data, m + 16 + 2 * segs, segs, U16)
		c.deltas = records(data, m + 16 + 4 * segs, segs, I16)
		c.ranges_at = m + 16 + 6 * segs
		c.ranges = records(data, c.ranges_at, segs, U16)
		if c.ranges == nil && segs > 0 {
			return {}, .Bad_Table
		}
	case 6:
		c.first = int(read_u16(data, m + 6))
		c.glyphs = records(data, m + 10, int(read_u16(data, m + 8)), U16)
	case 12, 13:
		c.groups = records(data, m + 16, int(read_u32(data, m + 12)), Group)
	}
	return c, nil
}

// The face's cmap subtable for (platform, encoding), in a format read
// here, for codes that aren't Unicode: PDF's symbolic TrueType fonts look
// codes up in (3, 0), at 0xF000 + the code, or in (1, 0), Mac Roman.
// `cmap_glyph` maps through it.
cmap_subtable :: proc(f: ^Face, platform, encoding: u16) -> (c: Cmap, ok: bool) {
	d, cmap := f.data, f.tables[.cmap].at
	for i in 0 ..< (int(read_u16(d, cmap + 2)) if cmap != 0 else 0) {
		rec := cmap + 4 + 8 * i
		if read_u16(d, rec) == platform && read_u16(d, rec + 2) == encoding {
			at := cmap + int(read_u32(d, rec + 4))
			if cmap_format_read(read_u16(d, at)) {
				err: Error
				c, err = cmap_read(d, at)
				return c, err == nil
			}
		}
	}
	return
}

// ---- characters and metrics -----------------------------------------------------------

// The glyph for code point `r`; 0 (the missing glyph) when the face has
// none.
glyph_index :: proc(f: ^Face, r: rune) -> Glyph {
	return cmap_glyph(f, &f.cmap, r)
}

// The glyph a subtable of the face's cmap (`f.cmap`, or one from
// `cmap_subtable`) maps `code` to; 0 when it maps none.
cmap_glyph :: proc(f: ^Face, c: ^Cmap, code: rune) -> Glyph {
	if code < 0 {
		return 0
	}
	cp := int(code)
	switch c.format {
	case 0:
		if cp < len(c.bytes) {
			return Glyph(c.bytes[cp])
		}
	case 4:
		// The first segment ending at or after cp.
		i, _ := slice.binary_search_by(c.ends, cp, proc(e: U16, cp: int) -> slice.Ordering {
			return slice.cmp(int(e.v), cp)
		})
		if i == len(c.ends) || cp < int(c.starts[i].v) {
			return 0
		}
		if c.ranges[i].v == 0 {
			return Glyph(cp + int(c.deltas[i].v))
		}
		g := read_u16(f.data, c.ranges_at + 2 * i + int(c.ranges[i].v) + 2 * (cp - int(c.starts[i].v)))
		return Glyph(int(g) + int(c.deltas[i].v)) if g != 0 else 0
	case 6:
		if cp >= c.first && cp - c.first < len(c.glyphs) {
			return Glyph(c.glyphs[cp - c.first].v)
		}
	case 12, 13:
		i, found := slice.binary_search_by(c.groups, u32(cp), proc(g: Group, cp: u32) -> slice.Ordering {
			return .Less if u32(g.last) < cp else (.Greater if u32(g.first) > cp else .Equal)
		})
		if found {
			g := c.groups[i]
			return Glyph(g.glyph) if c.format == 13 else Glyph(u32(g.glyph) + u32(cp) - u32(g.first))
		}
	}
	return 0
}

// The glyph's advance width and left side bearing (font units): hmtx's,
// or for a face without it (`load_cff`, `load_type1`) its charstring's
// width, rounded, and Type 1's side bearing or the left edge of a CFF
// glyph's points (`glyph_box`'s); 0 when they can't be read.
h_metrics :: proc(f: ^Face, g: Glyph) -> (advance, left_side_bearing: int) {
	if f.tables[.hmtx].at == 0 {
		width, sbx, ok := charstring_width(f, g)
		if !ok {
			return
		}
		advance = int(math.round(width))
		if f.t1.program != nil {
			left_side_bearing = int(math.round(sbx))
		} else if box, drawn := cff_outline(f, g, nil); drawn {
			left_side_bearing = box[0]
		}
		return
	}
	i := int(g)
	if i < len(f.metrics) {
		m := f.metrics[i]
		return int(m.advance), int(m.lsb)
	}
	if len(f.metrics) > 0 {
		advance = int(f.metrics[len(f.metrics) - 1].advance)
	}
	if j := i - len(f.metrics); j < len(f.bearings) {
		left_side_bearing = int(f.bearings[j].v)
	}
	return
}

// Scale from font units to pixels so ascent - descent is `height`.
scale_for_pixel_height :: proc(f: ^Face, height: f32) -> f32 {
	return height / f32(f.ascent - f.descent)
}

// Scale from font units to pixels for an em of `size` pixels.
scale_for_em :: proc(f: ^Face, size: f32) -> f32 {
	return size / f32(f.units_per_em)
}

