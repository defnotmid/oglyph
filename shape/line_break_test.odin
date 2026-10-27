package shape

import "core:testing"
import "core:unicode/utf8"

// Breaks as a layout reads them (Unicode's own test of every rule runs in
// tools/line_break_test): '.' none after a character, '|' allowed, '!'
// mandatory.
@(test)
test_line_breaks :: proc(t: ^testing.T) {
	marks :: proc(text: string) -> string {
		runes := utf8.string_to_runes(text, context.temp_allocator)
		breaks := make([]Line_Break, len(runes), context.temp_allocator)
		line_breaks(runes, breaks)
		out := make([]u8, len(breaks), context.temp_allocator)
		mark := [Line_Break]u8{.None = '.', .Allowed = '|', .Mandatory = '!'}
		for b, i in breaks {
			out[i] = mark[b]
		}
		return string(out)
	}
	cases := [?]struct {
		text, want: string,
	} {
		{"", ""},
		// After the space, not before it.
		{"hello world", ".....|....!"},
		{"a\nb", ".!!"},
		{"a\r\nb", "..!!"},
		// Numbers and abbreviations hold together.
		{"e.g. 3.14", "....|...!"},
		// Between ideographs, after a hyphen.
		{"日本語", "||!"},
		{"co-op", "..|.!"},
		// A combining mark goes with its letter.
		{"é a", "..|!"},
	}
	for c in cases {
		testing.expectf(t, marks(c.text) == c.want, "%q: got %s, want %s", c.text, marks(c.text), c.want)
	}
	// The class and the facts beside it.
	p := line_break_props(0xFF08)
	testing.expect_value(t, p.class, Line_Break_Class.OP)
	testing.expect(t, p.east_asian && !p.pictographic)
	testing.expect_value(t, line_break_props('“').class, Line_Break_Class.QU_Pi)
	testing.expect(t, line_break_props(0x1FFFD).pictographic)
}
