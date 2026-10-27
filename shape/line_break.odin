package shape

// Line break opportunities: the Unicode Line Breaking Algorithm (UAX #14),
// its default rules at UNICODE_VERSION, over the classes unicode_data.odin
// holds (resolved as LB1 resolves them by default: Thai, Lao, Khmer and
// Myanmar words, class SA, don't break inside, as no dictionary is used).

Line_Break :: enum u8 {
	// The line can't end here.
	None,
	// It may.
	Allowed,
	// It must: after a hard line break (BK, CR, LF, NL) and at the end of
	// the text.
	Mandatory,
}

// A code point's line breaking class and the two facts the rules ask
// besides.
Line_Break_Props :: bit_field u8 {
	class:        Line_Break_Class | 6,
	// East_Asian_Width F, W or H (LB19a, LB30).
	east_asian:   bool             | 1,
	// Extended_Pictographic and unassigned (LB30b).
	pictographic: bool             | 1,
}

line_break_props :: #force_inline proc "contextless" (r: rune) -> Line_Break_Props {
	cp := u32(r)
	if cp >= 0x110000 {
		return {class = .AL}
	}
	#no_bounds_check {
		block := u32(LB_STAGE1[cp >> LB_SHIFT])
		return transmute(Line_Break_Props)LB_BLOCKS[block + cp & (1 << LB_SHIFT - 1)]
	}
}

// Where a line may or must end in `text`: out[i] is the break after
// text[i] (`out` holds at least len(text)); the last is Mandatory.
line_breaks :: proc "contextless" (text: []rune, out: []Line_Break) {
	n := len(text)
	if n == 0 {
		return
	}
	breaks := out[:n]
	// The units before and after the position, and the one after those.
	a, i := break_unit(text, 0)
	b, j := break_unit(text, i)
	for m in 0 ..< i - 1 {
		breaks[m] = .None
	}
	s := Break_Context{before = SOT, left = a if a.class != .SP else SOT, left_before = SOT, numeric = a.class == .NU, ri = 1 if a.class == .RI else 0}
	for i < n {
		c, k := break_unit(text, j)
		breaks[i - 1] = break_between(&s, a, b, c, text, k)
		for m in i ..< j - 1 {
			breaks[m] = .None
		}
		s.numeric_close = (b.class == .CL || b.class == .CP) && s.numeric
		s.numeric = b.class == .NU || ((b.class == .SY || b.class == .IS) && s.numeric)
		s.ri = s.ri + 1 if b.class == .RI else 0
		if b.class != .SP {
			s.left, s.left_before = b, a
		}
		s.before = a
		a, b = b, c
		i, j = j, k
	}
	breaks[n - 1] = .Mandatory
}

// A character with the combining marks and joiners it takes (LB9), as the
// rules after LB9 see it.
@(private = "file")
Break_Unit :: struct {
	class:        Line_Break_Class,
	east_asian:   bool,
	pictographic: bool,
	// U+25CC DOTTED CIRCLE (LB28a).
	dotted:       bool,
	// Its last character is a zero width joiner (LB8a).
	joiner:       bool,
}

// The start and the end of the text act as a hard line break: every rule
// naming sot or eot names BK with it, or asks only that it isn't East
// Asian.
@(private = "file")
SOT :: Break_Unit{class = .BK}

// What the rules look back at, besides the unit before the position.
@(private = "file")
Break_Context :: struct {
	// The unit before that one.
	before:        Break_Unit,
	// The last unit that isn't a space (X in X SP*), and the one before it.
	left:          Break_Unit,
	left_before:   Break_Unit,
	// The unit before the position ends NU (SY | IS)*, or is CL or CP
	// after it (LB25).
	numeric:       bool,
	numeric_close: bool,
	// Regional indicators ending at the unit before the position (LB30a).
	ri:            int,
}

// The unit starting at text[i] and where the next starts. A character
// takes the marks and joiners after it unless it is a hard break, a space
// or a zero width space (LB9); a mark or joiner no character takes is A
// (LB10). Past the end: eot.
@(private = "file")
break_unit :: #force_inline proc "contextless" (text: []rune, i: int) -> (u: Break_Unit, next: int) {
	if i >= len(text) {
		return SOT, i
	}
	p := line_break_props(text[i])
	u = {class = p.class, east_asian = p.east_asian, pictographic = p.pictographic, dotted = text[i] == 0x25CC, joiner = p.class == .ZWJ}
	next = i + 1
	#partial switch u.class {
	case .BK, .CR, .LF, .NL, .SP, .ZW:
		return
	case .CM, .ZWJ:
		u = {class = .AL, joiner = u.joiner}
	}
	for next < len(text) {
		c := line_break_props(text[next]).class
		if c != .CM && c != .ZWJ {
			break
		}
		u.joiner = c == .ZWJ
		next += 1
	}
	return
}

// The rules in order, between unit `a` and unit `b`; `c` follows `b`, and
// the unit after `c` starts at text[after_c].
@(private = "file")
break_between :: proc "contextless" (s: ^Break_Context, a, b, c: Break_Unit, text: []rune, after_c: int) -> Line_Break {
	quote :: #force_inline proc "contextless" (u: Break_Unit) -> bool {
		return u.class == .QU || u.class == .QU_Pi || u.class == .QU_Pf
	}
	letter :: #force_inline proc "contextless" (u: Break_Unit) -> bool {
		return u.class == .AL || u.class == .HL
	}
	aksara :: #force_inline proc "contextless" (u: Break_Unit) -> bool {
		return u.class == .AK || u.class == .AS || u.dotted
	}
	A, B := a.class, b.class
	// LB4-LB8a: hard breaks, spaces, zero width space, joiners.
	switch {
	case A == .BK:
		return .Mandatory
	case A == .CR && B == .LF:
		return .None
	case A == .CR || A == .LF || A == .NL:
		return .Mandatory
	case B == .BK || B == .CR || B == .LF || B == .NL, B == .SP || B == .ZW:
		return .None
	case A == .ZW || (A == .SP && s.left.class == .ZW):
		return .Allowed
	case a.joiner:
		return .None
	}
	L := s.left.class
	// LB11-LB18: joiners, glue, punctuation around spaces.
	switch {
	case A == .WJ || B == .WJ, A == .GL:
		return .None
	case B == .GL && A != .SP && A != .BA && A != .HY && A != .HH:
		return .None
	case B == .CL || B == .CP || B == .EX || B == .SY:
		return .None
	case L == .OP:
		return .None
	case L == .QU_Pi && (s.left_before.class == .BK || s.left_before.class == .CR || s.left_before.class == .LF || s.left_before.class == .NL || s.left_before.class == .OP || quote(s.left_before) || s.left_before.class == .GL || s.left_before.class == .SP || s.left_before.class == .ZW):
		return .None
	case B == .QU_Pf:
		#partial switch c.class {
		case .SP, .GL, .WJ, .CL, .QU, .QU_Pi, .QU_Pf, .CP, .EX, .IS, .SY, .BK, .CR, .LF, .NL, .ZW:
			return .None
		}
	}
	switch {
	case A == .SP && B == .IS && c.class == .NU:
		return .Allowed
	case B == .IS:
		return .None
	case (L == .CL || L == .CP) && B == .NS, L == .B2 && B == .B2:
		return .None
	case A == .SP:
		return .Allowed
	}
	// LB19-LB22: quotation marks, contingent breaks, hyphens.
	switch {
	case B == .QU || B == .QU_Pf, A == .QU || A == .QU_Pi:
		return .None
	case quote(b) && (!a.east_asian || !c.east_asian), quote(a) && (!b.east_asian || !s.before.east_asian):
		return .None
	case A == .CB || B == .CB:
		return .Allowed
	}
	P := s.before.class
	switch {
	case (A == .HY || A == .HH) && (P == .BK || P == .CR || P == .LF || P == .NL || P == .SP || P == .ZW || P == .CB || P == .GL) && letter(b):
		return .None
	case B == .BA || B == .HH || B == .HY || B == .NS, A == .BB:
		return .None
	case (A == .HY || A == .HH) && P == .HL && B != .HL, A == .SY && B == .HL, B == .IN:
		return .None
	}
	// LB23-LB27: numbers, Korean syllables.
	switch {
	case letter(a) && B == .NU, A == .NU && letter(b):
		return .None
	case A == .PR && (B == .ID || B == .EB || B == .EM), (A == .ID || A == .EB || A == .EM) && B == .PO:
		return .None
	case (A == .PR || A == .PO) && letter(b), letter(a) && (B == .PR || B == .PO):
		return .None
	case (s.numeric_close || s.numeric) && (B == .PO || B == .PR):
		return .None
	case (A == .PO || A == .PR) && B == .OP && (c.class == .NU || (c.class == .IS && break_next_class(text, after_c) == .NU)):
		return .None
	case (A == .PO || A == .PR || A == .HY || A == .IS) && B == .NU, s.numeric && B == .NU:
		return .None
	case A == .JL && (B == .JL || B == .JV || B == .H2 || B == .H3), (A == .JV || A == .H2) && (B == .JV || B == .JT), (A == .JT || A == .H3) && B == .JT:
		return .None
	case (A == .JL || A == .JV || A == .JT || A == .H2 || A == .H3) && B == .PO, A == .PR && (B == .JL || B == .JV || B == .JT || B == .H2 || B == .H3):
		return .None
	}
	// LB28-LB30b: letters, Brahmic syllables, parentheses, flags, emoji.
	switch {
	case letter(a) && letter(b):
		return .None
	case A == .AP && aksara(b), aksara(a) && (B == .VF || B == .VI):
		return .None
	case A == .VI && aksara(s.before) && (B == .AK || b.dotted), aksara(a) && aksara(b) && c.class == .VF:
		return .None
	case A == .IS && letter(b):
		return .None
	case (letter(a) || A == .NU) && B == .OP && !b.east_asian, A == .CP && !a.east_asian && (letter(b) || B == .NU):
		return .None
	case A == .RI && B == .RI && s.ri % 2 == 1:
		return .None
	case B == .EM && (A == .EB || a.pictographic):
		return .None
	}
	return .Allowed
}

@(private = "file")
break_next_class :: proc "contextless" (text: []rune, i: int) -> Line_Break_Class {
	u, _ := break_unit(text, i)
	return u.class
}
