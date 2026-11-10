package font

import "core:math"

// Variable fonts: fvar's axes and named instances, avar's remapping of
// normalized coordinates, ItemVariationStore deltas (HVAR advances, GDEF
// and GPOS device deltas) and, in gvar.odin, glyph outline deltas.
//
// A face is one instance: `set_variations` (user values per axis tag) or
// `set_coords` (normalized) choose it, and outlines, advances and shaping
// follow it. All zero coordinates are the default instance, where every
// read gives what the font's static tables say. Loading the same data
// twice gives two instances.

// A face with more axes than this stays at its default instance. Tables
// varying over a different number of axes than fvar's (the spec requires
// the same) give no deltas.
MAX_AXES :: 64

Axis :: struct {
	tag:                string,
	min, default, max:  f32,
	// Not meant for users to set (fvar's HIDDEN_AXIS flag).
	hidden:             bool,
	name_id:            u16,
}

// A setting of one axis in user units (wght 700, wdth 87.5).
Variation :: struct {
	tag:   string,
	value: f32,
}

@(private)
fixed :: #force_inline proc "contextless" (d: []u8, at: int) -> f32 {
	return f32(i32(read_u32(d, at))) / 65536
}

// Axis `i` of the face (false past the last).
axis :: proc(f: ^Face, i: int) -> (a: Axis, ok: bool) {
	d, fvar := f.data, f.tables[.fvar].at
	if fvar == 0 || i < 0 || i >= f.axis_count {
		return
	}
	at := fvar + int(read_u16(d, fvar + 4)) + i * int(read_u16(d, fvar + 10))
	if at + 20 > len(d) {
		return
	}
	a.tag = string(d[at:at + 4])
	a.min, a.default, a.max = fixed(d, at + 4), fixed(d, at + 8), fixed(d, at + 12)
	a.hidden = read_u16(d, at + 16) & 1 != 0
	a.name_id = read_u16(d, at + 18)
	return a, true
}

// The named instances fvar lists.
instance_count :: proc(f: ^Face) -> int {
	fvar := f.tables[.fvar].at
	return int(read_u16(f.data, fvar + 12)) if fvar != 0 else 0
}

// Named instance `i`: its subfamily name id, and its user coordinate per
// axis in `values` (as many as fit).
instance :: proc(f: ^Face, i: int, values: []f32) -> (subfamily_name_id: u16, ok: bool) {
	d, fvar := f.data, f.tables[.fvar].at
	if fvar == 0 || i < 0 || i >= instance_count(f) {
		return
	}
	axes := int(read_u16(d, fvar + 8))
	at := fvar + int(read_u16(d, fvar + 4)) + axes * int(read_u16(d, fvar + 10)) + i * int(read_u16(d, fvar + 14))
	for k in 0 ..< min(len(values), axes) {
		values[k] = fixed(d, at + 4 + 4 * k)
	}
	return read_u16(d, at), at + 4 + 4 * axes <= len(d)
}

// Chooses the instance by user values per axis tag; axes not named take
// their default. Normalizing and avar's remapping work in 16.16 fixed
// point, rounded to 2.14 at the end (HarfBuzz's precision, to review: 2.14
// between the steps loses a unit at some values).
set_variations :: proc(f: ^Face, settings: []Variation) {
	n: [MAX_AXES]f32
	for i in 0 ..< f.axis_count {
		a, _ := axis(f, i)
		for s in settings {
			if s.tag == a.tag {
				n[i] = normalize_axis_value(a, s.value)
			}
		}
	}
	avar_map(f, n[:f.axis_count])
	f.coords = {}
	for v, i in n[:f.axis_count] {
		f.coords[i] = i16(clamp(math.floor(v * 16384 + 0.5), -16384, 16384))
	}
}

// Chooses the instance by normalized coordinates (2.14), avar applied
// already; missing axes take their default.
set_coords :: proc(f: ^Face, coords: []i16) {
	f.coords = {}
	copy(f.coords[:f.axis_count], coords)
}

// A user value's normalized coordinate: -1 at the minimum, 0 at the
// default, 1 at the maximum (to 16.16). In single precision, rounded half
// away from zero, as HarfBuzz does (to review), so instances near a
// rounding boundary pick the same coordinate.
@(private)
normalize_axis_value :: proc(a: Axis, v: f32) -> f32 {
	lo, hi := min(a.default, a.min), max(a.default, a.max)
	c, def := clamp(v, lo, hi), a.default
	n: f32
	if c < def {
		n = (c - def) / (def - lo)
	} else if c > def {
		n = (c - def) / (hi - def)
	}
	return fixed_16_16(n)
}

@(private)
fixed_16_16 :: proc(v: f32) -> f32 {
	return math.round(v * 65536) / 65536
}

// avar: each axis's normalized coordinate through its segment map (pairs
// of from and to coordinates, 2.14, in order); version 2 then adds each
// axis's delta from its ItemVariationStore at the mapped coordinates.
@(private)
avar_map :: proc(f: ^Face, coords: []f32) {
	d, avar := f.data, f.tables[.avar].at
	version := read_u16(d, avar)
	if avar == 0 || (version != 1 && version != 2) {
		return
	}
	at := avar + 8
	axis_count := int(read_u16(d, avar + 6))
	if axis_count != len(coords) {
		return
	}
	for i in 0 ..< axis_count {
		count := int(read_u16(d, at))
		pairs := at + 2
		at = pairs + 4 * count
		from :: proc(d: []u8, pairs, k: int) -> f32 {
			return f32(read_i16(d, pairs + 4 * k)) / 16384
		}
		to :: proc(d: []u8, pairs, k: int) -> f32 {
			return f32(read_i16(d, pairs + 4 * k + 2)) / 16384
		}
		v := coords[i]
		switch {
		case count == 0:
		case count == 1 || v <= from(d, pairs, 0):
			v = v - from(d, pairs, 0) + to(d, pairs, 0)
		case:
			k := 1
			for k < count - 1 && v > from(d, pairs, k) {
				k += 1
			}
			if v >= from(d, pairs, k) {
				v = v - from(d, pairs, k) + to(d, pairs, k)
			} else if from(d, pairs, k - 1) == from(d, pairs, k) {
				v = to(d, pairs, k - 1)
			} else {
				f0, f1 := from(d, pairs, k - 1), from(d, pairs, k)
				t0, t1 := to(d, pairs, k - 1), to(d, pairs, k)
				v = t0 + (t1 - t0) * (v - f0) / (f1 - f0)
			}
		}
		coords[i] = fixed_16_16(clamp(v, -1, 1))
	}
	if version != 2 {
		return
	}
	m, store := int(read_u32(d, at)), int(read_u32(d, at + 4))
	if store == 0 {
		return
	}
	// In 16.16 and 2.14 integers, as HarfBuzz does.
	mapped: [MAX_AXES]i16
	for v, i in coords {
		mapped[i] = i16(math.round(v * 16384))
	}
	axis_map := delta_set_map(d, avar + m if m != 0 else 0)
	for &v, i in coords {
		outer, inner := delta_set_index(d, &axis_map, i)
		delta := item_variation_delta(d, avar + store, outer, inner, mapped[:len(coords)])
		c := v * 65536 + math.round(clamp(delta * 4, -131072, 131072))
		v = clamp(c, -65536, 65536) / 65536
	}
}

// Whether the face is at an instance other than the default.
has_variation :: proc(f: ^Face) -> bool {
	for c in f.coords[:f.axis_count] {
		if c != 0 {
			return true
		}
	}
	return false
}

// ---- ItemVariationStore -------------------------------------------------------------

// The delta of item (outer, inner) of the ItemVariationStore at `store`
// at an instance: the sum of each region's delta scaled by how far the
// instance lies within the region. `instance` is its normalized
// coordinates, or each region's scalar there (region_scalars), worked out
// once for many items.
item_variation_delta :: proc(d: []u8, store: int, outer, inner: int, instance: $T) -> f32 where T == []i16 || T == []f32 {
	if store == 0 || read_u16(d, store) != 1 || outer >= int(read_u16(d, store + 6)) {
		return 0
	}
	regions := store + int(read_u32(d, store + 2))
	list_count := int(read_u16(d, regions + 2))
	when T == []i16 {
		axes, _, ok := region_list(d, regions, instance)
		if !ok {
			return 0
		}
	} else {
		// Scalars of another store's regions are none of this one's.
		if len(instance) != list_count {
			return 0
		}
	}
	data := store + int(read_u32(d, store + 8 + 4 * outer))
	item_count := int(read_u16(d, data))
	word_count := int(read_u16(d, data + 2))
	long_words := word_count & 0x8000 != 0
	word_count &= 0x7FFF
	region_count := int(read_u16(d, data + 4))
	size: int = 2 if long_words else 1
	row_size := (2 * word_count + region_count - word_count) * size
	if inner >= item_count || word_count > region_count || data + 6 + 2 * region_count + item_count * row_size > len(d) {
		return 0
	}
	row := data + 6 + 2 * region_count + inner * row_size
	delta: f32
	for k in 0 ..< region_count {
		region := int(read_u16(d, data + 6 + 2 * k))
		if region >= list_count {
			continue
		}
		scalar: f32
		when T == []i16 {
			scalar = region_scalar(d, regions + 4 + region * axes * 6, axes, instance)
		} else {
			scalar = instance[region]
		}
		if scalar == 0 {
			continue
		}
		// The row's word columns (two bytes each, four when long), then
		// the rest (one byte each, two when long).
		v: i32
		if k < word_count {
			at := row + 2 * size * k
			v = i32(read_u32(d, at)) if long_words else i32(read_i16(d, at))
		} else {
			at := row + size * (word_count + k)
			v = i32(read_i16(d, at)) if long_words else i32(i8(read_u8(d, at)))
		}
		delta += f32(v) * scalar
	}
	return delta
}

// The scalar (region_scalar) of each region of the ItemVariationStore at
// `store` at the coordinates, into `out`, for reading many of its items
// at one instance: none when it has none to give.
region_scalars :: proc(d: []u8, store: int, coords: []i16, out: ^[dynamic]f32) {
	clear(out)
	if store == 0 || read_u16(d, store) != 1 {
		return
	}
	regions := store + int(read_u32(d, store + 2))
	axes, count, ok := region_list(d, regions, coords)
	if !ok {
		return
	}
	resize(out, count)
	for &scalar, r in out {
		scalar = region_scalar(d, regions + 4 + r * axes * 6, axes, coords)
	}
}

// The VariationRegionList at `at`: its axis count and regions, ok when it
// varies over the face's axes and lies within the data (so evaluating it
// reads no more than the font holds).
@(private)
region_list :: proc(d: []u8, at: int, coords: []i16) -> (axes, count: int, ok: bool) {
	axes, count = int(read_u16(d, at)), int(read_u16(d, at + 2))
	return axes, count, axes == len(coords) && at + 4 + 6 * axes * count <= len(d)
}

// How much of a region (start, peak, end per axis) the coordinates are
// in: 1 at its peaks, falling to 0 at its edges.
@(private)
region_scalar :: proc(d: []u8, at, axes: int, coords: []i16) -> f32 {
	scalar: f32 = 1
	for i in 0 ..< axes {
		r := at + 6 * i
		start, peak, end := int(read_i16(d, r)), int(read_i16(d, r + 2)), int(read_i16(d, r + 4))
		v := int(coords[i]) if i < len(coords) else 0
		if peak == 0 || v == peak {
			continue
		}
		if v == 0 {
			return 0
		}
		if start > peak || peak > end || (start < 0 && end > 0) {
			continue
		}
		if v <= start || v >= end {
			return 0
		}
		if v < peak {
			scalar *= f32(v - start) / f32(peak - start)
		} else {
			scalar *= f32(end - v) / f32(end - peak)
		}
	}
	return scalar
}

// A DeltaSetIndexMap, its header read (count 0: none, the identity).
@(private)
Delta_Set_Map :: struct {
	data, count, entry_size: int,
	inner_bits:              uint,
}

// The DeltaSetIndexMap at `m` (0 for none).
@(private)
delta_set_map :: proc(d: []u8, m: int) -> (dsm: Delta_Set_Map) {
	if m == 0 {
		return
	}
	entry_format := int(read_u8(d, m + 1))
	if read_u8(d, m) == 0 {
		dsm.count, dsm.data = int(read_u16(d, m + 2)), m + 4
	} else {
		dsm.count, dsm.data = int(read_u32(d, m + 2)), m + 6
	}
	dsm.entry_size = (entry_format >> 4 & 3) + 1
	dsm.inner_bits = uint(entry_format & 0xF) + 1
	return
}

// The (outer, inner) item the map gives entry `i` (the last entry for
// those past it; the identity without a map).
@(private)
delta_set_index :: proc(d: []u8, dsm: ^Delta_Set_Map, i: int) -> (outer, inner: int) {
	if dsm.count == 0 {
		return 0, i
	}
	e := min(i, dsm.count - 1)
	entry: u32
	for k in 0 ..< dsm.entry_size {
		entry = entry << 8 | u32(read_u8(d, dsm.data + e * dsm.entry_size + k))
	}
	return int(entry >> dsm.inner_bits), int(entry & (1 << dsm.inner_bits - 1))
}

// floor(x + 0.5) as an int, as HarfBuzz rounds deltas: for the finite
// values deltas are, without math.floor's modf.
round_delta :: #force_inline proc "contextless" (x: f32) -> int {
	y := x + 0.5
	i := int(y)
	return i - 1 if f32(i) > y else i
}

// What reading glyphs' advances at a face's instance takes, read once:
// whether it varies, HVAR's store and map, and its regions' scalars.
Advances :: struct {
	varied:      bool,
	store:       int, // 0 without HVAR
	advance_map: Delta_Set_Map,
	// nil: worked out per glyph from the coordinates.
	scalars:     []f32,
}

// Reads `f`'s HVAR for advance_at, its regions' scalars into `scalars`
// when given (for many glyphs).
advances_init :: proc(f: ^Face, scalars: ^[dynamic]f32 = nil) -> (a: Advances) {
	if scalars != nil {
		clear(scalars)
	}
	a.varied = has_variation(f)
	d := f.data
	hvar := f.tables[.HVAR].at
	if !a.varied || hvar == 0 || read_u16(d, hvar) != 1 {
		return
	}
	a.store = hvar + int(read_u32(d, hvar + 4))
	if m := int(read_u32(d, hvar + 8)); m != 0 {
		a.advance_map = delta_set_map(d, hvar + m)
	}
	if scalars != nil {
		region_scalars(d, a.store, f.coords[:f.axis_count], scalars)
		a.scalars = scalars[:]
	}
	return
}

// The glyph's advance width at the face's instance (font units, rounded):
// hmtx's, plus HVAR's delta, else the phantom points gvar moves.
advance_at :: proc(f: ^Face, a: ^Advances, g: Glyph) -> int {
	adv, _ := h_metrics(f, g)
	if !a.varied {
		return adv
	}
	if a.store != 0 {
		d := f.data
		outer, inner := delta_set_index(d, &a.advance_map, int(g))
		delta := item_variation_delta(d, a.store, outer, inner, a.scalars) if a.scalars != nil else item_variation_delta(d, a.store, outer, inner, f.coords[:f.axis_count])
		return max(adv + round_delta(delta), 0)
	}
	if f.tables[.gvar].at != 0 && f.tables[.glyf].at != 0 {
		if v, ok := gvar_advance(f, g); ok {
			return v
		}
	}
	return adv
}

// advance_at for one glyph.
advance :: proc(f: ^Face, g: Glyph) -> int {
	a := advances_init(f)
	return advance_at(f, &a, g)
}
