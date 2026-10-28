package collection

import "core:sync"
import "core:testing"
import "core:thread"
import "core:unicode/utf8"

import sh "../shape"

VERA :: #load("../assets/Vera.ttf")
MONO :: #load("../assets/JetBrainsMono-Regular.ttf")
ARABIC :: #load("../assets/NotoSansArabic-Bold.ttf")

// Faces are found by family (any case), then style, then the nearest
// weight; a family the collection lacks gives the fallback, which answers
// to its own family. Ids stay with their faces as faces are added before
// them, and name nothing once removed or from another collection.
@(test)
test_collection_find_and_ids :: proc(t: ^testing.T) {
	c: Collection
	testing.expect(t, collection_init(&c, VERA))
	defer collection_destroy(&c)
	testing.expect_value(t, collection_add(&c, MONO), 1)
	mono := c.faces[0].id
	testing.expect_value(t, c.faces[0].family, "JetBrains Mono")
	id, found := collection_find(&c, "jetbrains mono", 700)
	testing.expect(t, found && id == mono)
	id, found = collection_find(&c, "Nope", 400)
	testing.expect(t, !found && id == c.fallback.id)
	id, found = collection_find(&c, "Bitstream Vera Sans", 400)
	testing.expect(t, found && id == c.fallback.id)
	// Added before it: the face moves down the order, its id and its row
	// stay.
	row := collection_face(&c, mono)
	testing.expect_value(t, collection_add(&c, ARABIC, before = 0), 1)
	testing.expect(t, c.faces[1].id == mono && collection_face(&c, mono) == c.faces[1] && c.faces[1] == row)
	other: Collection
	testing.expect(t, collection_init(&other, VERA))
	defer collection_destroy(&other)
	testing.expect(t, collection_face(&other, mono) == nil)
	collection_remove(&c, 1)
	testing.expect(t, collection_face(&c, mono) == nil)
	testing.expect(t, collection_face(&c, Face_Id{}) == nil)
}

// A character the asked-for face lacks takes the first face with it; one
// no face has keeps the face asked for.
@(test)
test_collection_fallback :: proc(t: ^testing.T) {
	c: Collection
	testing.expect(t, collection_init(&c, VERA))
	defer collection_destroy(&c)
	collection_add(&c, MONO)
	collection_add(&c, ARABIC)
	mono, arabic := c.faces[0].id, c.faces[1].id
	text := utf8.string_to_runes("aب \U0010FFFD", context.temp_allocator)
	piece := make([]i32, len(text), context.temp_allocator)
	faces := make([]Face_Id, len(text), context.temp_allocator)
	for &f in faces {
		f = mono
	}
	collection_fallback(&c, text, piece, faces)
	testing.expect(t, faces[0] == mono)
	testing.expect(t, faces[1] == arabic)
	testing.expect(t, faces[2] == mono)
	testing.expect(t, faces[3] == mono)
}

// Collections sharing their files share each file's row and its plans.
@(test)
test_collection_shared_files :: proc(t: ^testing.T) {
	// Rows are found by the bytes' address: each file's bytes once.
	vera, mono := VERA, MONO
	files: Files
	files_init(&files)
	defer files_destroy(&files)
	a, b: Collection
	testing.expect(t, collection_init(&a, vera, files = &files))
	defer collection_destroy(&a)
	testing.expect(t, collection_init(&b, vera, files = &files))
	defer collection_destroy(&b)
	collection_add(&a, mono)
	collection_add(&b, mono)
	testing.expect(t, a.faces[0].file == b.faces[0].file)
	testing.expect_value(t, len(files.rows), 2)
	pa := file_plan(&files, a.faces[0], .Latin, .LTR, nil)
	pb := file_plan(&files, b.faces[0], .Latin, .LTR, nil)
	testing.expect(t, pa == pb)
	testing.expect(t, file_plan(&files, b.faces[0], .Latin, .LTR, {{tag = sh.tag("liga")}}) != pa)
}

// Rows never move: a row's place holds across chunk after chunk of rows
// added, and a row past every chunk is nil.
@(test)
test_rows_stay :: proc(t: ^testing.T) {
	r: Rows(int)
	defer rows_destroy(&r)
	testing.expect(t, rows_at(&r, 0) == nil)
	first: ^int
	for i in 0 ..< 1000 {
		k, row := rows_append(&r, i * 3)
		testing.expect_value(t, k, i)
		if i == 0 {
			first = row
		}
	}
	testing.expect(t, rows_at(&r, 0) == first && first^ == 0)
	for i in 0 ..< 1000 {
		testing.expect_value(t, rows_at(&r, i)^, i * 3)
	}
	testing.expect(t, rows_at(&r, 1 << 20) == nil)
}

// A face's pointer holds while faces are added on another thread: a reader
// resolving ids handed to it before (through a lock, as a caller's would)
// reads them while the writer adds a hundred more, past several chunks.
@(test)
test_collection_add_while_reading :: proc(t: ^testing.T) {
	c: Collection
	testing.expect(t, collection_init(&c, VERA))
	defer collection_destroy(&c)
	collection_add(&c, MONO)
	Shared :: struct {
		c:         ^Collection,
		ids:       [2]Face_Id,
		rows:      [2]^Face,
		lock:      sync.Mutex,
		done:      bool,
		mismatches: int,
	}
	s := Shared{c = &c}
	sync.mutex_lock(&s.lock)
	s.ids = {c.fallback.id, c.faces[0].id}
	s.rows = {c.fallback, c.faces[0]}
	sync.mutex_unlock(&s.lock)
	reader := thread.create_and_start_with_data(&s, proc(data: rawptr) {
		s := (^Shared)(data)
		sync.mutex_lock(&s.lock)
		ids, rows := s.ids, s.rows
		sync.mutex_unlock(&s.lock)
		for !sync.atomic_load(&s.done) {
			for id, k in ids {
				f := collection_face(s.c, id)
				if f != rows[k] || f.id != id || len(f.family) == 0 {
					sync.atomic_add(&s.mismatches, 1)
				}
			}
		}
	})
	for _ in 0 ..< 100 {
		collection_add(&c, ARABIC)
	}
	sync.atomic_store(&s.done, true)
	thread.join(reader)
	thread.destroy(reader)
	testing.expect_value(t, s.mismatches, 0)
	testing.expect_value(t, len(c.faces), 101)
	testing.expect(t, collection_face(&c, s.ids[1]) == s.rows[1])
}
