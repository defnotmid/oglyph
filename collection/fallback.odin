package collection

import "core:unicode"

import ft "../font"
import sh "../shape"

// Which face draws each character: the face its text asks for, else the
// first face that has it (per-glyph fallback), emoji sequences kept in one
// colour face and combining marks with their base.

// The face each character of `text` draws with: `faces` holds the face its
// text asks for (one per piece: piece[i] is the run of text it belongs to)
// and is rewritten with the face fallback picks. A character the asked-for face
// lacks takes the first face with it (collection_glyph); an emoji
// presentation sequence takes a colour face and its joiners, selectors
// and modifiers stay with what they follow; a combining mark of another
// face than its base takes its cluster (one piece) to the first face that
// has it all.
collection_fallback :: proc(c: ^Collection, text: []rune, piece: []i32, faces: []Face_Id) {
	n := len(text)
	// The highest codepoint: emoji and mark fallback have nothing to do
	// below the first they look at.
	top: rune
	// A piece at a time: its characters asked for one face.
	for i := 0; i < n; {
		want, p := faces[i], piece[i]
		j := i
		face := collection_face(c, want)
		if face == nil {
			for j < n && piece[j] == p {
				top = max(top, text[j])
				j += 1
			}
			i = j
			continue
		}
		// The face's characters, as its shaping tables map them.
		cmap := &file_shaping(c.files, face.file, &face.face).cmap
		bitmaps := c.outlines_only && face.bitmap_colour
		for j < n && piece[j] == p {
			r := text[j]
			if r != '\n' && r != ' ' && r != '\t' {
				g := ft.Glyph(sh.two_level_get(cmap, int(r)))
				if g == 0 || (bitmaps && ft.glyph_empty(&face.face, g)) {
					if f, fg := collection_glyph(c, r, want); fg != 0 {
						faces[j] = f
					}
				}
			}
			top = max(top, r)
			j += 1
		}
		i = j
	}
	if top >= 0x200D {
		emoji_fallback(c, text, faces)
	}
	if top >= 0x300 {
		mark_fallback(c, text, piece, faces)
	}
}

// The face with a glyph for `r`: `primary`, else the first of `faces`,
// then the emoji face, then the fallback; `primary` and 0 when none has
// one.
collection_glyph :: proc(c: ^Collection, r: rune, primary: Face_Id) -> (Face_Id, ft.Glyph) {
	if f := collection_face(c, primary); f != nil {
		if g := glyph_drawable(c, f, ft.glyph_index(&f.face, r)); g != 0 {
			return primary, g
		}
	}
	for f in c.faces {
		if f.id != primary {
			if g := glyph_drawable(c, f, ft.glyph_index(&f.face, r)); g != 0 {
				return f.id, g
			}
		}
	}
	if e := c.emoji; e != nil {
		if g := ft.glyph_index(&e.face, r); g != 0 {
			return e.id, g
		}
	}
	if g := ft.glyph_index(&c.fallback.face, r); g != 0 {
		return c.fallback.id, g
	}
	return primary, 0
}

// The first colour (COLR) face with a glyph for `r`: added faces, then the
// emoji face; Face_Id{} and 0 when none has one.
collection_emoji_glyph :: proc(c: ^Collection, r: rune) -> (Face_Id, ft.Glyph) {
	for f in c.faces {
		if f.colour {
			if g := ft.glyph_index(&f.face, r); g != 0 {
				return f.id, g
			}
		}
	}
	if e := c.emoji; e != nil && e.colour {
		if g := ft.glyph_index(&e.face, r); g != 0 {
			return e.id, g
		}
	}
	return {}, 0
}

// `g`, or 0 where the collection's renderer draws outlines only and the
// face has only a bitmap for it.
glyph_drawable :: #force_inline proc(c: ^Collection, f: ^Face, g: ft.Glyph) -> ft.Glyph {
	if g != 0 && c.outlines_only && f.bitmap_colour && ft.glyph_empty(&f.face, g) {
		return 0
	}
	return g
}

// Keeps emoji sequences in one face so they shape into one glyph: a rune
// asking for emoji presentation (U+FE0F after it, or after a joiner in a
// colour face) takes a colour face, and joiners, variation selectors,
// skin-tone modifiers, keycaps and tags stay in the face of the rune before.
@(private = "file")
emoji_fallback :: proc(c: ^Collection, runes: []rune, face: []Face_Id) {
	continues :: proc(r: rune) -> bool {
		return r == 0x200D || r == 0xFE0E || r == 0xFE0F || r == 0x20E3 || (r >= 0x1F3FB && r <= 0x1F3FF) || (r >= 0xE0020 && r <= 0xE007F)
	}
	colour :: proc(c: ^Collection, id: Face_Id) -> bool {
		f := collection_face(c, id)
		return f != nil && f.colour
	}
	for i in 0 ..< len(runes) {
		r := runes[i]
		if i > 0 && runes[i - 1] != '\n' && continues(r) {
			face[i] = face[i - 1]
			continue
		}
		wants := i + 1 < len(runes) && runes[i + 1] == 0xFE0F
		wants ||= i > 0 && runes[i - 1] == 0x200D && colour(c, face[i - 1])
		if wants && !colour(c, face[i]) {
			if f, g := collection_emoji_glyph(c, r); g != 0 {
				face[i] = f
			}
		}
	}
}

// A combining mark that fell back to another face than its base's takes
// the cluster (base and its marks) to the first such face that has them
// all: marks attach to their base only when shaped with it. Runes that kept
// their neighbour's face cost one comparison.
@(private = "file")
mark_fallback :: proc(c: ^Collection, char: []rune, piece: []i32, face: []Face_Id) {
	is_mark :: proc(r: rune) -> bool {
		return unicode.is_nonspacing_mark(r) || unicode.is_enclosing_mark(r) || unicode.is_spacing_mark(r)
	}
	n := len(char)
	for i := 1; i < n; i += 1 {
		if face[i] == face[i - 1] || !is_mark(char[i]) {
			continue
		}
		// The cluster: back to its base, on to its last mark (one piece).
		base := i - 1
		for base > 0 && is_mark(char[base]) && piece[base - 1] == piece[i] {
			base -= 1
		}
		end := i + 1
		for end < n && is_mark(char[end]) && piece[end] == piece[i] {
			end += 1
		}
		if piece[base] != piece[i] {
			i = end - 1
			continue
		}
		for k in base ..< end {
			id := face[k]
			f := collection_face(c, id)
			has_all := f != nil
			for j in base ..< end {
				if !has_all || glyph_drawable(c, f, ft.glyph_index(&f.face, char[j])) == 0 {
					has_all = false
					break
				}
			}
			if has_all {
				for j in base ..< end {
					face[j] = id
				}
				break
			}
		}
		i = end - 1
	}
}
