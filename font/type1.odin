package font

import "base:runtime"
import "core:math"
import "core:slice"
import "core:strconv"

// Type 1 fonts (PostScript's, as PFB, PFA or PDF's FontFile): the font's
// eexec part decrypted, its charstrings decrypted in place, and tables of
// spans into that program, in memory the face owns. Its charstrings run
// through the CFF interpreter (cff.odin), whose Type 1 operators these
// are: hsbw and sbw, closepath, seac, div, and flex and hint replacement
// through OtherSubrs.
Type1 :: struct {
	// The decoded program: the cleartext, then the eexec part's plaintext.
	program:     []u8,
	// Per glyph (CharStrings' order, .notdef first): its name and its
	// charstring, [start, end) in the program; Subrs' charstrings.
	names:       [][2]u32,
	charstrings: [][2]u32,
	subrs:       [][2]u32,
	// The glyphs sorted by name, and each code's glyph in the font's
	// Encoding.
	by_name:     []u32,
	encoding:    []Glyph,
	font_matrix: matrix[2, 3]f32,
	// The allocation names through encoding are carved from, and what it
	// and program came from.
	tables:      []u32,
	allocator:   runtime.Allocator,
}

// Reads a Type 1 font: a PFB (segments), PFA, or PDF's FontFile (its
// cleartext, then its eexec part, binary or hex), into memory of its own
// from `allocator`, freed by `face_destroy`. Its glyphs are addressed by
// id (CharStrings' order, .notdef first) and named (`glyph_names`), and
// its Encoding (`builtin_encoding`) and FontMatrix (`glyph_matrix`) are
// read; like a bare CFF it has no metrics or cmap.
load_type1 :: proc(data: []u8, allocator := context.allocator) -> (f: Face, err: Error) {
	program := make([]u8, len(data), allocator)
	n := type1_decode(data, program)
	if n < 0 {
		delete(program, allocator)
		return {}, .Not_A_Font
	}
	t := &f.t1
	t.program = program[:n]
	t.allocator = allocator
	// Counted, then filled.
	p := Type1_Parse{}
	type1_parse(t.program, &p)
	if p.glyphs == 0 {
		delete(program, allocator)
		return {}, .Bad_Table
	}
	t.tables = make([]u32, 4 * p.glyphs + 2 * p.subrs + p.glyphs + 128, allocator)
	rest := t.tables
	carve :: proc(rest: ^[]u32, n: int) -> []u32 {
		s := rest[:n]
		rest^ = rest[n:]
		return s
	}
	t.names = slice.reinterpret([][2]u32, carve(&rest, 2 * p.glyphs))
	t.charstrings = slice.reinterpret([][2]u32, carve(&rest, 2 * p.glyphs))
	t.subrs = slice.reinterpret([][2]u32, carve(&rest, 2 * p.subrs))
	t.by_name = carve(&rest, p.glyphs)
	t.encoding = slice.reinterpret([]Glyph, carve(&rest, 128))
	p = {
		names       = t.names,
		charstrings = t.charstrings,
		subrs_out   = t.subrs,
	}
	type1_parse(t.program, &p)
	// .notdef is glyph 0.
	for i in 0 ..< p.glyphs {
		if type1_text(t, t.names[i]) == ".notdef" {
			t.names[0], t.names[i] = t.names[i], t.names[0]
			t.charstrings[0], t.charstrings[i] = t.charstrings[i], t.charstrings[0]
			break
		}
	}
	type1_sort_names(t)
	for code in 0 ..< 256 {
		name := string(CFF_STRINGS[encoding_sid(STANDARD_ENCODING[:], code)]) if p.standard else type1_text(t, p.encoding[code])
		if name != "" && name != ".notdef" {
			t.encoding[code] = type1_glyph(t, name)
		}
	}
	t.font_matrix = p.font_matrix if p.font_matrix_ok else {0.001, 0, 0, 0, 0.001, 0}
	f.data = t.program
	f.glyph_count = p.glyphs
	f.units_per_em = 1000
	if s := abs(t.font_matrix[0, 0]); s >= 1.0 / 0xffff && s <= 1 {
		f.units_per_em = int(math.round(1 / s))
	}
	return f, nil
}

// Frees what `load_type1` allocated (nothing for any other face) and
// clears the face.
face_destroy :: proc(f: ^Face) {
	t := &f.t1
	if t.program != nil {
		delete(t.program, t.allocator)
		delete(t.tables, t.allocator)
	}
	f^ = {}
}

@(private)
type1_text :: proc(t: ^Type1, span: [2]u32) -> string {
	return string(t.program[span[0]:span[1]])
}

// by_name: the glyphs in order of their names.
@(private)
type1_sort_names :: proc(t: ^Type1) {
	Named :: struct {
		name: string,
		g:    u32,
	}
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	named := make([]Named, len(t.by_name), context.temp_allocator)
	for &x, g in named {
		x = {type1_text(t, t.names[g]), u32(g)}
	}
	slice.sort_by(named, proc(a, b: Named) -> bool {return a.name < b.name})
	for x, i in named {
		t.by_name[i] = x.g
	}
}

// The glyph named `name`; 0 for none.
@(private)
type1_glyph :: proc(t: ^Type1, name: string) -> Glyph {
	lo, hi := 0, len(t.by_name)
	for lo < hi {
		mid := (lo + hi) / 2
		if type1_text(t, t.names[t.by_name[mid]]) < name {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < len(t.by_name) && type1_text(t, t.names[t.by_name[lo]]) == name {
		return Glyph(t.by_name[lo])
	}
	return 0
}

// ---- decoding ---------------------------------------------------------------------

@(private)
EEXEC_KEY :: 55665

@(private)
CHARSTRING_KEY :: 4330

// One byte of Type 1's cipher.
@(private)
decrypt :: #force_inline proc "contextless" (c: u8, r: ^u16) -> u8 {
	p := c ~ u8(r^ >> 8)
	r^ = (u16(c) + r^) * 52845 + 22719
	return p
}

@(private)
is_space :: proc "contextless" (c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == 0
}

@(private)
hex_value :: proc "contextless" (c: u8) -> int {
	switch c {
	case '0' ..= '9':
		return int(c - '0')
	case 'a' ..= 'f':
		return int(c - 'a' + 10)
	case 'A' ..= 'F':
		return int(c - 'A' + 10)
	}
	return -1
}

// Writes the font's program to `out` (at least len(data) bytes): its
// cleartext, then its eexec part decrypted (without the cipher's 4 leading
// bytes); how long, -1 when it isn't a Type 1 font.
@(private)
type1_decode :: proc(data: []u8, out: []u8) -> int {
	n := 0
	r := u16(EEXEC_KEY)
	skip := 4
	plain :: proc(out: []u8, n: ^int, c: u8, r: ^u16, skip: ^int) {
		p := decrypt(c, r)
		if skip^ > 0 {
			skip^ -= 1
		} else {
			out[n^] = p
			n^ += 1
		}
	}
	if read_u8(data, 0) == 0x80 {
		// PFB: segments of a type (1 text, 2 binary, 3 the end) and a
		// 32-bit little-endian length.
		binary := false
		for at := 0; at + 6 <= len(data) && data[at] == 0x80; {
			kind := data[at + 1]
			size := int(data[at + 2]) | int(data[at + 3]) << 8 | int(data[at + 4]) << 16 | int(data[at + 5]) << 24
			at += 6
			if kind == 3 {
				break
			}
			seg := data[at:][:min(size, len(data) - at)]
			at += len(seg)
			switch kind {
			case 1:
				if binary {
					// The trailer (zeros, cleartomark): not part of the program.
					continue
				}
				n += copy(out[n:], seg)
			case 2:
				binary = true
				for c in seg {
					plain(out, &n, c, &r, &skip)
				}
			case:
				return -1
			}
		}
		return n if binary else -1
	}
	// The cleartext ends after "eexec" and its white space.
	at := -1
	for i in 0 ..< len(data) - 4 {
		if string(data[i:][:5]) == "eexec" {
			at = i + 5
			break
		}
	}
	if at < 0 || read_u8(data, 0) != '%' || read_u8(data, 1) != '!' {
		return -1
	}
	for at < len(data) && is_space(data[at]) {
		at += 1
	}
	n = copy(out, data[:at])
	hex := at + 4 <= len(data)
	for i in 0 ..< 4 {
		hex = hex && hex_value(read_u8(data, at + i)) >= 0
	}
	if hex {
		high := -1
		for c in data[at:] {
			v := hex_value(c)
			if v < 0 {
				if !is_space(c) {
					break
				}
				continue
			}
			if high < 0 {
				high = v
			} else {
				plain(out, &n, u8(high << 4 | v), &r, &skip)
				high = -1
			}
		}
	} else {
		for c in data[at:] {
			plain(out, &n, c, &r, &skip)
		}
	}
	return n
}

// ---- parsing ----------------------------------------------------------------------

@(private)
Token_Kind :: enum u8 {
	End,
	// /name
	Literal,
	// An executable name or operator.
	Name,
	Number,
	String,
	Open_Array,
	Close_Array,
	Open_Proc,
	Close_Proc,
	Other,
}

@(private)
Token :: struct {
	kind:    Token_Kind,
	at, end: int,
}

@(private)
is_delimiter :: proc "contextless" (c: u8) -> bool {
	switch c {
	case '(', ')', '<', '>', '[', ']', '{', '}', '/', '%':
		return true
	}
	return is_space(c)
}

// The PostScript token at `pos^` (moving past it); a literal's span is its
// name without the slash.
@(private)
next_token :: proc(d: []u8, pos: ^int) -> Token {
	i := pos^
	for i < len(d) {
		if is_space(d[i]) {
			i += 1
		} else if d[i] == '%' {
			for i < len(d) && d[i] != '\n' && d[i] != '\r' {
				i += 1
			}
		} else {
			break
		}
	}
	if i >= len(d) {
		pos^ = i
		return {.End, i, i}
	}
	start := i
	t := Token{.Other, start, start + 1}
	switch d[i] {
	case '/':
		i += 1
		for i < len(d) && !is_delimiter(d[i]) {
			i += 1
		}
		t = {.Literal, start + 1, i}
	case '(':
		depth := 0
		for i < len(d) {
			c := d[i]
			i += 1
			if c == '\\' {
				i += 1
			} else if c == '(' {
				depth += 1
			} else if c == ')' {
				depth -= 1
				if depth == 0 {
					break
				}
			}
		}
		t = {.String, start, min(i, len(d))}
	case '<':
		if read_u8(d, i + 1) == '<' {
			t.end = i + 2
		} else {
			for i < len(d) && d[i] != '>' {
				i += 1
			}
			t = {.String, start, min(i + 1, len(d))}
		}
	case '>':
		if read_u8(d, i + 1) == '>' {
			t.end = i + 2
		}
	case '[':
		t.kind = .Open_Array
	case ']':
		t.kind = .Close_Array
	case '{':
		t.kind = .Open_Proc
	case '}':
		t.kind = .Close_Proc
	case ')':
	case:
		for i < len(d) && !is_delimiter(d[i]) {
			i += 1
		}
		t = {.Name, start, i}
		if _, ok := strconv.parse_f64(string(d[start:i])); ok {
			t.kind = .Number
		}
	}
	pos^ = t.end
	return t
}

@(private)
token_number :: proc(d: []u8, t: Token) -> f64 {
	x, _ := strconv.parse_f64(string(d[t.at:t.end]))
	return x
}

@(private)
token_is :: proc(d: []u8, t: Token, kind: Token_Kind, text: string) -> bool {
	return t.kind == kind && string(d[t.at:t.end]) == text
}

// What a pass over the program finds: counts (and spans into the tables
// given, decrypting their charstrings in place).
@(private)
Type1_Parse :: struct {
	glyphs, subrs:   int,
	len_iv:          int,
	standard:        bool,
	font_matrix:     matrix[2, 3]f32,
	font_matrix_ok:  bool,
	// Each code's glyph name in a custom Encoding.
	encoding:        [256][2]u32,
	// Filled when not nil.
	names:           [][2]u32,
	charstrings:     [][2]u32,
	subrs_out:       [][2]u32,
}

// The binary data after `n RD` at `pos^` (one space, then n bytes),
// decrypted in place when filling, without its lenIV bytes.
@(private)
type1_binary :: proc(d: []u8, pos: ^int, n: int, len_iv: int, fill: bool) -> [2]u32 {
	at := min(pos^ + 1, len(d))
	end := min(at + max(n, 0), len(d))
	pos^ = end
	if len_iv < 0 {
		return {u32(at), u32(end)}
	}
	if fill {
		r := u16(CHARSTRING_KEY)
		for &c in d[at:end] {
			c = decrypt(c, &r)
		}
	}
	return {u32(min(at + len_iv, end)), u32(end)}
}

@(private)
type1_parse :: proc(d: []u8, p: ^Type1_Parse) {
	fill := p.names != nil
	p.len_iv = 4
	p.glyphs = 0
	pos := 0
	prev: Token
	for {
		t := next_token(d, &pos)
		if t.kind == .End {
			return
		}
		// Binary data the font holds elsewhere: skipped.
		if prev.kind == .Number && (token_is(d, t, .Name, "RD") || token_is(d, t, .Name, "-|")) {
			type1_binary(d, &pos, int(token_number(d, prev)), -1, false)
		}
		prev = t
		if t.kind != .Literal {
			continue
		}
		switch string(d[t.at:t.end]) {
		case "FontMatrix":
			if open := next_token(d, &pos); open.kind == .Open_Array || open.kind == .Open_Proc {
				v: [6]f32
				p.font_matrix_ok = true
				for &x in v {
					n := next_token(d, &pos)
					if n.kind != .Number {
						p.font_matrix_ok = false
						break
					}
					x = f32(token_number(d, n))
				}
				p.font_matrix = {v[0], v[2], v[4], v[1], v[3], v[5]}
			}
		case "Encoding":
			e := next_token(d, &pos)
			if token_is(d, e, .Name, "StandardEncoding") {
				p.standard = true
				continue
			}
			// dup code /name put, up to def.
			for {
				e = next_token(d, &pos)
				if e.kind == .End || token_is(d, e, .Name, "def") || token_is(d, e, .Name, "readonly") {
					break
				}
				if !token_is(d, e, .Name, "dup") {
					continue
				}
				code, name := next_token(d, &pos), next_token(d, &pos)
				if code.kind == .Number && name.kind == .Literal {
					if c := int(token_number(d, code)); c >= 0 && c < 256 {
						p.encoding[c] = {u32(name.at), u32(name.end)}
					}
				}
			}
		case "lenIV":
			if n := next_token(d, &pos); n.kind == .Number {
				p.len_iv = int(token_number(d, n))
			}
		case "Subrs":
			n := next_token(d, &pos)
			if n.kind != .Number {
				continue
			}
			p.subrs = max(int(token_number(d, n)), 0)
			// dup index n RD <binary> NP, ...
			for {
				back := pos
				e := next_token(d, &pos)
				if token_is(d, e, .Name, "dup") {
					i, size, rd := next_token(d, &pos), next_token(d, &pos), next_token(d, &pos)
					if i.kind != .Number || size.kind != .Number || rd.kind != .Name {
						break
					}
					span := type1_binary(d, &pos, int(token_number(d, size)), p.len_iv, fill)
					if k := int(token_number(d, i)); fill && k >= 0 && k < len(p.subrs_out) {
						p.subrs_out[k] = span
					}
				} else if e.kind == .Name && (token_is(d, e, .Name, "array") || token_is(d, e, .Name, "NP") || token_is(d, e, .Name, "|") || token_is(d, e, .Name, "noaccess") || token_is(d, e, .Name, "put")) {
					continue
				} else {
					pos = back
					break
				}
			}
		case "CharStrings":
			if next_token(d, &pos).kind != .Number || p.glyphs > 0 {
				continue
			}
			// /name n RD <binary> ND, ... up to end.
			for {
				e := next_token(d, &pos)
				if e.kind == .End || token_is(d, e, .Name, "end") {
					break
				}
				if e.kind != .Literal {
					continue
				}
				size, rd := next_token(d, &pos), next_token(d, &pos)
				if size.kind != .Number || rd.kind != .Name {
					break
				}
				span := type1_binary(d, &pos, int(token_number(d, size)), p.len_iv, fill)
				if fill && p.glyphs < len(p.names) {
					p.names[p.glyphs] = {u32(e.at), u32(e.end)}
					p.charstrings[p.glyphs] = span
				}
				p.glyphs += 1
			}
		}
	}
}

// ---- charstrings ------------------------------------------------------------------

@(private)
type1_charstring :: proc(t: ^Type1, g: Glyph) -> []u8 {
	if int(g) >= len(t.charstrings) {
		return nil
	}
	return t.program[t.charstrings[g][0]:t.charstrings[g][1]]
}

@(private)
type1_subr :: proc(t: ^Type1, n: f64) -> []u8 {
	i := int(n)
	if f64(i) != n || i < 0 || i >= len(t.subrs) {
		return nil
	}
	return t.program[t.subrs[i][0]:t.subrs[i][1]]
}

// seac's operands asb adx ady bchar achar: the base glyph, then the
// accent with its origin at (adx + sbx - asb, ady), where its own hsbw
// places it (fontTools' and FreeType's reading).
@(private)
type1_seac :: proc(f: ^Face, pen: ^Pen, v: []f64, sbx: f64) -> bool {
	glyph :: proc(t: ^Type1, code: f64) -> Glyph {
		k := int(code)
		sid := encoding_sid(STANDARD_ENCODING[:], k) if f64(k) == code else 0
		return type1_glyph(t, CFF_STRINGS[sid]) if sid != 0 else 0
	}
	base, accent := glyph(&f.t1, v[3]), glyph(&f.t1, v[4])
	if base == 0 || accent == 0 {
		return false
	}
	adx, ady, asb := v[1], v[2], v[0]
	pen_close(pen)
	origin := pen.origin
	pen.p = origin
	charstring(f, base, pen, false) or_return
	pen_close(pen)
	pen.origin = origin + {adx + sbx - asb, ady}
	pen.p = pen.origin
	ok := charstring(f, accent, pen, false)
	pen.origin = origin
	return ok
}
