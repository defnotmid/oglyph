package collection

import "core:hash"
import "core:math"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:unicode"

import ft "../font"
import sh "../shape"

// A set of font faces found by family, weight and style (CSS font
// matching), with per-glyph fallback through every face (fallback.odin),
// their files' shaping tables and plans shared (files.odin). Face data is
// borrowed and must outlive the collection.

// A face of a Collection, for as long as the collection holds it: the
// collection that made it and the face's row in its `rows`. Faces added
// before or after it keep it, a removed face's id names no face, and ids
// aren't reused; Face_Id{} names none, and neither does an id another
// collection made. A face never moves: its pointer (collection_face) holds
// until it is removed, while other threads add faces.
Face_Id :: struct {
	collection: u32,
	index:      u32,
}

// A face at an instance, as shaping and matching read it.
Face :: struct {
	face:          ft.Face,
	// Borrowed TTF/OTF bytes, and the face's index in a collection file.
	data:          []u8,
	index:         i32,
	family:        string, // its file's
	weight:        int,
	italic:        bool,
	// The variable font instance it is, as a key: 0 for the default, else a
	// hash of the face's coordinates.
	instance:      u64,
	// The FeatureVariations record its GSUB and GPOS lookups follow
	// (sh.plan_variations): instances with the same records share plans.
	plan_records:  [sh.Table_Kind]i32,
	// Has COLR / CPAL colour glyphs, or only bitmap colour glyphs (sbix,
	// CBDT).
	colour:        bool,
	bitmap_colour: bool,
	id:            Face_Id,
	// The font file face it is an instance of: a row of the collection's
	// `files`.
	file:          ^File,
}

Collection :: struct {
	// Every face the collection made, by id (Face_Id.index; the fallback's
	// is 0), where it stays: rows never move, so a face can be read on one
	// thread while another adds faces. Its allocator is the collection's
	// (collection_allocator).
	rows:           Rows(Face),
	// The faces matched and fallen back through, in order (collection_add's
	// `before`): rows of `rows`.
	faces:          [dynamic]^Face,
	// The font files its faces are instances of: collection_init's, shared
	// with other collections, else its own (`owns_files`).
	files:          ^Files,
	owns_files:     bool,
	// Used when nothing matches, and as the last fallback for glyphs (row 0).
	fallback:       ^Face,
	// Colour emoji face tried after `faces` (collection_set_emoji), nil
	// without one; never matched by family.
	emoji:          ^Face,
	// The family text that names none is drawn in (borrowed); empty, or a
	// family no face has: every face competes by weight and style.
	default_family: string,
	// The renderer's rule: a glyph a face has only as a bitmap (in a face
	// with bitmap colour glyphs) counts as missing, for fallback.
	outlines_only:  bool,
	// Which collection this is (Face_Id.collection), set with its first id.
	serial:         u32,
	// Per face id, its face's index in `faces`; -1 for the fallback, the
	// emoji face and faces gone.
	places:         [dynamic]i32,
	// The faces of `faces` by a hash of their family (family_hash),
	// ascending, with what finding one scores: a family's faces lie
	// together, so a find is a binary search and a sweep of its run, not a
	// scan of every face.
	by_family:      [dynamic]Family_Entry,
}

@(private)
Family_Entry :: struct {
	hash:   u64,
	face:   Face_Id,
	// The face's (its family string, borrowed).
	family: string,
	weight: i32,
	italic: bool,
}

@(private = "file")
PLACE_NONE :: -1

// Reads face `index` of a font or collection file at the instance
// `variations` pick (user values per axis tag, `{{"wght", 700}}`; axes not
// named keep their default). Family, weight and style are left to the
// collection that adds it.
face_load :: proc(data: []u8, index: i32 = 0, variations: []ft.Variation = nil) -> (face: Face, ok: bool) {
	f, err := ft.load(data, int(index))
	if err != nil {
		return {}, false
	}
	if len(variations) > 0 {
		ft.set_variations(&f, variations)
		if ft.has_variation(&f) {
			face.instance = hash.fnv64a(mem.slice_to_bytes(f.coords[:f.axis_count])) | 1
		}
	}
	face.face, face.data, face.index = f, data, index
	face.plan_records = sh.plan_variations(&f)
	face.colour = f.tables[.COLR].size >= 14 && f.tables[.CPAL].size >= 14
	face.bitmap_colour = !face.colour && (f.tables[.sbix].at != 0 || f.tables[.CBDT].at != 0)
	return face, true
}

// Family name (typographic family, else family), OS/2 weight class and
// italic bit of a face's tables.
face_identity :: proc(face: ^ft.Face, allocator := context.allocator) -> (family: string, weight: int, italic: bool) {
	weight = 400
	family = ft.name_string(face, 16, allocator)
	if family == "" {
		family = ft.name_string(face, 1, allocator)
	}
	if os2 := face.tables[.OS2]; os2.size >= 64 {
		weight = int(ft.read_u16(face.data, os2.at + 4))
		italic = ft.read_u16(face.data, os2.at + 62) & 1 != 0
	}
	if family == "" {
		family = strings.clone("Unknown", allocator)
	}
	return
}

// A collection falling back to the face `fallback_data` holds, whose faces'
// files are `files` (shared with the other collections given it), else a
// table of its own. `outlines_only`: see Collection.
collection_init :: proc(c: ^Collection, fallback_data: []u8, allocator := context.allocator, files: ^Files = nil, outlines_only := false) -> bool {
	rows_init(&c.rows, allocator)
	c.faces = make([dynamic]^Face, allocator)
	c.places = make([dynamic]i32, allocator)
	c.by_family = make([dynamic]Family_Entry, allocator)
	c.files = files
	c.outlines_only = outlines_only
	face := face_load(fallback_data) or_return
	face.file = file_row(collection_files(c), &face)
	face.family, face.weight, face.italic = face.file.family, face.file.weight, face.file.italic
	collection_serial(c)
	face.id = c.fallback.id
	c.fallback^ = face
	return true
}

collection_destroy :: proc(c: ^Collection) {
	allocator := collection_allocator(c)
	rows_destroy(&c.rows)
	delete(c.faces)
	delete(c.places)
	delete(c.by_family)
	if c.owns_files {
		files_destroy(c.files)
		free(c.files, allocator)
	}
	c^ = {}
}

// The collection's allocator: its faces'.
collection_allocator :: proc(c: ^Collection) -> mem.Allocator {
	if c.rows.allocator.procedure != nil {
		return c.rows.allocator
	}
	return context.allocator
}

// Sets the colour emoji face, tried for glyphs no face has and preferred for
// emoji presentation sequences (U+FE0F); a face it replaces is gone. The
// data is borrowed. Not while other threads read the collection.
collection_set_emoji :: proc(c: ^Collection, data: []u8) -> (id: Face_Id, ok: bool) {
	face := face_load(data) or_return
	if c.emoji != nil {
		c.emoji.id = {}
	}
	face.file = file_row(collection_files(c), &face)
	face.family, face.weight, face.italic = face.file.family, face.file.weight, face.file.italic
	c.emoji = face_add(c, face, PLACE_NONE)
	return c.emoji.id, true
}

// Adds every face of a TTF/OTF/TTC, in order before face `before` (at the
// end when past the last), variable ones at the instance `variations` pick
// (face_load). Family, weight and style come from the font's tables, the
// weight from a wght setting and the style from ital or slnt when given.
// Faces of data added before (to this collection or one sharing its
// files) share its file's tables and plans: another instance costs about
// its glyphs. Returns how many faces were added: faces[at:][:added], `at`
// being `before`, else the end. Other threads may read faces they hold the ids
// of meanwhile (collection_face: faces never move), but not match or fall
// back through the collection.
collection_add :: proc(c: ^Collection, data: []u8, before := max(int), variations: []ft.Variation = nil) -> (added: int) {
	allocator := collection_allocator(c)
	// A collection never initialized takes its allocator here, not from
	// the first append.
	c.rows.allocator = allocator
	c.faces.allocator = allocator
	c.by_family.allocator = allocator
	files := collection_files(c)
	for index in 0 ..< 64 {
		face, ok := face_load(data, i32(index), variations)
		if !ok {
			break
		}
		face.file = file_row(files, &face)
		face.family, face.weight, face.italic = face.file.family, face.file.weight, face.file.italic
		for v in variations {
			switch v.tag {
			case "wght":
				face.weight = int(math.round(v.value))
			case "ital":
				face.italic = v.value >= 0.5
			case "slnt":
				face.italic = v.value != 0
			}
		}
		row := face_add(c, face, i32(len(c.faces)))
		append(&c.faces, row)
		h := family_hash(row.family)
		inject_at(&c.by_family, family_first(c, h), Family_Entry{h, row.id, row.family, i32(row.weight), row.italic})
		added += 1
	}
	if at := len(c.faces) - added; before < at {
		slice.rotate_right(c.faces[max(before, 0):], added)
		face_places(c, max(before, 0))
	}
	return added
}

// Removes face `i` (of `faces`), whose id names no face after it (its file
// stays in the collection's files). Not while other threads read the
// collection.
collection_remove :: proc(c: ^Collection, i: int) {
	face := c.faces[i]
	c.places[face.id.index] = PLACE_NONE
	h := family_hash(face.family)
	for k := family_first(c, h); k < len(c.by_family) && c.by_family[k].hash == h; k += 1 {
		if c.by_family[k].face == face.id {
			ordered_remove(&c.by_family, k)
			break
		}
	}
	face.id = {}
	ordered_remove(&c.faces, i)
	face_places(c, i)
}

// Face `id`, where it stays until it is removed (adding faces moves none,
// so other threads may add faces meanwhile); nil once the face is removed
// (or, for an emoji face, replaced), for Face_Id{}, for an id of another
// collection and without a collection. It reads only the face's row.
collection_face :: proc(c: ^Collection, id: Face_Id) -> ^Face {
	if c == nil || id.collection == 0 || id.collection != c.serial {
		return nil
	}
	if f := rows_at(&c.rows, int(id.index)); f != nil && f.id == id {
		return f
	}
	return nil
}

// The next of the process's collection serials, from 1.
@(private = "file")
serial_next :: proc "contextless" () -> u32 {
	return sync.atomic_add(&serials, 1) + 1
}

@(private = "file")
serials: u32

// The collection's serial and its fallback's row (0), made with its first
// face: collection_init's fallback, else the first face added (the
// fallback then a zero face).
@(private = "file")
collection_serial :: proc(c: ^Collection) {
	if c.serial != 0 {
		return
	}
	if c.places.allocator.procedure == nil {
		c.places.allocator = collection_allocator(c)
	}
	c.serial = serial_next()
	_, c.fallback = rows_append(&c.rows, Face{id = {c.serial, 0}})
	append(&c.places, PLACE_NONE)
}

// Adds `face` as a new row with a new id, its index in `faces` at `place`
// (PLACE_NONE for none).
@(private = "file")
face_add :: proc(c: ^Collection, face: Face, place: i32) -> ^Face {
	collection_serial(c)
	face := face
	face.id = {c.serial, u32(c.rows.len)}
	_, row := rows_append(&c.rows, face)
	append(&c.places, place)
	return row
}

// A hash of a family name that names equal under strings.equal_fold
// share: each character taken as the least of its case-fold orbit
// (unicode.simple_fold), as equal_fold compares them.
@(private = "file")
family_hash :: proc(family: string) -> u64 {
	h: u64 = 0xcbf29ce484222325
	for r in family {
		least := r
		if r < 0x80 {
			if r >= 'a' && r <= 'z' {
				least = r - ('a' - 'A')
			}
		} else {
			for f := unicode.simple_fold(r); f != r; f = unicode.simple_fold(f) {
				least = min(least, f)
			}
		}
		h = (h ~ u64(least)) * 0x100000001b3
	}
	return h
}

// The first entry of `by_family` at or past hash `h`.
@(private = "file")
family_first :: proc(c: ^Collection, h: u64) -> int {
	lo, hi := 0, len(c.by_family)
	for lo < hi {
		mid := (lo + hi) / 2
		if c.by_family[mid].hash < h {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// The places of faces[from:], after they moved in `faces`.
@(private = "file")
face_places :: proc(c: ^Collection, from: int) {
	for f, i in c.faces[from:] {
		c.places[f.id.index] = i32(from + i)
	}
}

// The collection's files, a table of its own made for a collection
// without one.
@(private = "file")
collection_files :: proc(c: ^Collection) -> ^Files {
	if c.files == nil {
		allocator := collection_allocator(c)
		c.files = new(Files, allocator)
		files_init(c.files, allocator)
		c.owns_files = true
	}
	return c.files
}

// The best face for `family` (case-insensitive): with `variations`, one
// whose instance they pick first; matching style next, then the nearest
// weight (0 means 400). An empty family is `default_family`
// when the collection has it, else every face competes (earlier faces win
// ties). `found = false` gives the fallback face, which is also found by
// its own family (so `default_family` may name it).
collection_find :: proc(c: ^Collection, family: string, weight: int, italic := false, variations: []ft.Variation = nil) -> (face: Face_Id, found: bool) {
	if family == "" && c.default_family != "" {
		if f, ok := collection_find(c, c.default_family, weight, italic, variations); ok {
			return f, true
		}
	}
	want := weight if weight > 0 else 400
	// The best by score, then by place (earlier faces win ties).
	best := -1
	best_score := max(int)
	score :: #force_inline proc(f: ^Face, weight: int, face_italic: bool, want: int, italic: bool, variations: []ft.Variation) -> int {
		s := abs(weight - want) * 2 + (0 if face_italic == italic else 10000)
		if len(variations) > 0 && !picks_instance(f, variations) {
			s += 1 << 30
		}
		return s
	}
	if family == "" {
		// No family asked for: every face competes, the first of the right
		// style winning.
		for f, i in c.faces {
			if sc := i + score(f, f.weight, f.italic, want, italic, variations); sc < best_score {
				best, best_score = i, sc
			}
		}
	} else {
		// The family's run of the index, scored from its entries.
		h := family_hash(family)
		for k := family_first(c, h); k < len(c.by_family) && c.by_family[k].hash == h; k += 1 {
			e := &c.by_family[k]
			if e.family != family && !strings.equal_fold(e.family, family) {
				continue
			}
			at := int(c.places[e.face.index])
			if sc := score(c.faces[at], int(e.weight), e.italic, want, italic, variations); sc < best_score || (sc == best_score && at < best) {
				best, best_score = at, sc
			}
		}
	}
	if best < 0 {
		// The fallback face answers to its own family too.
		return c.fallback.id, family == "" || strings.equal_fold(family, c.fallback.family)
	}
	return c.faces[best].id, true
}

// Whether `variations` pick the instance the face is (a face without axes
// is the one instance any settings pick).
@(private = "file")
picks_instance :: proc(f: ^Face, variations: []ft.Variation) -> bool {
	face := f.face
	ft.set_variations(&face, variations)
	return face.coords == f.face.coords
}
