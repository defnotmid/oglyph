package shape

// Bidi levels of a line in a left-to-right paragraph (UAX #9 without
// explicit embeddings, isolates or bracket pairs): weak types resolved
// (W1-W7), neutrals between text of one direction take it and others the
// paragraph's (N1, N2), then levels 0 (L), 1 (R) and 2 (numbers in R text).

char_bidi_class :: #force_inline proc "contextless" (r: rune) -> Bidi_Class {
	return char_props(r).bidi
}

// Resolves each character's class (char_bidi_class; `classes` is rewritten)
// into its level.
bidi_levels :: proc "contextless" (classes: []Bidi_Class, levels: []u8) {
	cls := classes
	n := len(cls)
	// Without embeddings or isolates their controls are what X9 makes the
	// embedding ones, ignored, and isolates neutral, as are separators and
	// spaces.
	for &c in cls {
		#partial switch c {
		case .B, .S, .WS, .LRI, .RLI, .FSI, .PDI:
			c = .ON
		case .LRE, .LRO, .RLE, .RLO, .PDF:
			c = .BN
		}
	}
	// W1: marks and ignored format characters take the class before them.
	prev := Bidi_Class.L
	for &c in cls {
		if c == .NSM || c == .BN {
			c = prev
		}
		prev = c
	}
	// W2: European numbers after Arabic letters are Arabic numbers. W3:
	// Arabic letters are R.
	strong := Bidi_Class.L
	for &c in cls {
		#partial switch c {
		case .L, .R, .AL:
			strong = c
		case .EN:
			if strong == .AL {
				c = .AN
			}
		}
		if c == .AL {
			c = .R
		}
	}
	// W4: one separator between two numbers of a kind joins them.
	for i in 1 ..< n - 1 {
		a, b := cls[i - 1], cls[i + 1]
		if cls[i] == .ES && a == .EN && b == .EN {
			cls[i] = .EN
		} else if cls[i] == .CS && a == b && (a == .EN || a == .AN) {
			cls[i] = a
		}
	}
	// W5: terminators next to European numbers join them.
	for i := 0; i < n; {
		if cls[i] != .ET {
			i += 1
			continue
		}
		j := i
		for j < n && cls[j] == .ET {
			j += 1
		}
		if (i > 0 && cls[i - 1] == .EN) || (j < n && cls[j] == .EN) {
			for k in i ..< j {
				cls[k] = .EN
			}
		}
		i = j
	}
	// W6: other separators and terminators are neutral. W7: European
	// numbers after L text (or the paragraph start) are L.
	strong = .L
	for &c in cls {
		#partial switch c {
		case .ES, .CS, .ET:
			c = .ON
		case .L, .R:
			strong = c
		case .EN:
			if strong == .L {
				c = .L
			}
		}
	}
	// N1, N2: neutrals between text of one direction take it (numbers count
	// as R); others take the paragraph's, L.
	dir :: proc "contextless" (c: Bidi_Class) -> Bidi_Class {
		return .L if c == .L else .R
	}
	for i := 0; i < n; {
		if cls[i] != .ON {
			i += 1
			continue
		}
		j := i
		for j < n && cls[j] == .ON {
			j += 1
		}
		before := Bidi_Class.L if i == 0 else dir(cls[i - 1])
		after := Bidi_Class.L if j == n else dir(cls[j])
		d := before if before == after else Bidi_Class.L
		for k in i ..< j {
			cls[k] = d
		}
		i = j
	}
	// I1.
	for c, i in cls {
		levels[i] = 0 if c == .L else 1 if c == .R else 2
	}
}
