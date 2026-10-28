package collection

import "base:intrinsics"
import "core:mem"
import "core:sync"

// A table whose rows never move once added, so a row read on one thread
// stays put while another thread adds rows. Rows live in chunks of doubling
// size (chunk k holds ROWS_FIRST << k rows), found through a fixed table of
// chunk pointers: adding allocates a chunk at a time and copies nothing.
// One thread adds; a reader reads only rows whose index was handed to it
// after they were added.
Rows :: struct($T: typeid) {
	chunks:    [ROWS_CHUNKS][^]T,
	len:       int,
	allocator: mem.Allocator,
}

ROWS_FIRST :: 16
ROWS_CHUNKS :: 32

// The chunk row i lies in and its place there.
@(private = "file")
rows_slot :: #force_inline proc "contextless" (i: int) -> (chunk, at: int) {
	q := u64(i / ROWS_FIRST + 1)
	chunk = 63 - int(intrinsics.count_leading_zeros(q))
	at = i - ROWS_FIRST * ((1 << uint(chunk)) - 1)
	return
}

rows_init :: proc(r: ^Rows($T), allocator := context.allocator) {
	r^ = {}
	r.allocator = allocator
}

rows_destroy :: proc(r: ^Rows($T)) {
	for c, k in r.chunks {
		if c != nil {
			delete(c[:ROWS_FIRST << uint(k)], r.allocator)
		}
	}
	r^ = {}
}

// Row i: nil past every chunk added to (a row of a chunk that isn't added
// yet reads zero).
rows_at :: #force_inline proc "contextless" (r: ^Rows($T), i: int) -> ^T {
	if i < 0 {
		return nil
	}
	k, at := rows_slot(i)
	if k >= ROWS_CHUNKS {
		return nil
	}
	c := sync.atomic_load_explicit(&r.chunks[k], .Acquire)
	return &c[at] if c != nil else nil
}

// Adds row `v`: its index, and where it lives from now on.
rows_append :: proc(r: ^Rows($T), v: T) -> (index: int, row: ^T) {
	k, at := rows_slot(r.len)
	assert(k < ROWS_CHUNKS)
	c := r.chunks[k]
	if c == nil {
		if r.allocator.procedure == nil {
			r.allocator = context.allocator
		}
		c = raw_data(make([]T, ROWS_FIRST << uint(k), r.allocator))
		sync.atomic_store_explicit(&r.chunks[k], c, .Release)
	}
	c[at] = v
	index, row = r.len, &c[at]
	r.len += 1
	return
}
