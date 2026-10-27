module qrvy;

import std::math;

// ================================
// Public: Shader Functions
// ================================

fn void curve_to_glsl(DString* s, Point[] pts, String name)
{
	s.appendf("float %s(float x)\n{\n", name);
	s.appendf("    x = clamp(x, %s, %s);\n", num(pts[0].x), num(pts[^1].x));

	// Merge consecutive segments that are the same polynomial
	int n = (int)pts.len - 1;
	Seg[] runs = mem::talloc_array(Seg, n);
	int count = 0;
	for (int i = 0; i < n;)
	{
		Seg run = build_seg(pts, i, i + 1);
		int j = i + 1;
		while (j < n && same_poly(&run, &&build_seg(pts, j, j + 1))) j++;
		if (j > i + 1) run = build_seg(pts, i, j);
		runs[count++] = run;
		i = j;
	}

	// Symmetry only helps when there is at least one condition to remove
	double sx = (double)pts[0].x + pts[^1].x;
	double sy = (double)pts[0].y + pts[^1].y;
	Sym sym = count >= 2 ? detect_symmetry(runs, count, sx, sy) : Sym.NONE;

	switch (sym)
	{
		case NONE:
			emit_chain(s, runs, count, "x", "return ");

		case EVEN:
			s.appendf("    float u = min(x, %s);\n", sub_from(sx, "x"));
			emit_chain(s, runs, (count + 1) / 2, "u", "return ");

		case POINT:
			int half = (count + 1) / 2;
			s.appendf("    float u = min(x, %s);\n", sub_from(sx, "x"));
			if (half == 1)
			{
				emit_chain(s, runs, 1, "u", "float r = ");
			}
			else
			{
				s.append("    float r;\n");
				emit_chain(s, runs, half, "u", "r = ");
			}
			s.appendf("    return x < %s ? r : %s;\n", num((float)(sx * 0.5)), sub_from(sy, "r"));
	}
	s.append("}\n");
}

// ================================
// Local: IR
// ================================

enum Sym @local { NONE, EVEN, POINT }   // f(S-x) = f(x)  /  f(S-x) = Y - f(x)

struct Seg @local
{
	float x0, x1;
	float[4] c;      // printed coefficients of t^i, tiny ones zeroed
	double[4] d;     // exact coefficients of t^i
	double[4] gl;    // coefficients of x^i, for comparing segments
	int deg;         // highest non-zero degree
	int low;         // zero low-order coefficients, so t^low can be factored out
	bool remap;      // needs t = x*s + o
	double s, o;
}

// Hermite cubic in t = (x - x0) / dx, from pts[i] to pts[j]
fn Seg build_seg(Point[] pts, int i, int j) @local
{
	Vec2 p0 = pts[i].xy;
	Vec2 p1 = pts[j].xy;
	double dx = (double)p1.x - p0.x;
	double dy = (double)p1.y - p0.y;
	double ma = curve_tangent(pts, i);
	double mb = curve_tangent(pts, j);

	double[4] d = {
		p0.y,
		dx * ma,
		3.0 * dy - dx * (2.0 * ma + mb),
		-2.0 * dy + dx * (ma + mb),
	};

	Seg g;
	g.x0 = p0.x;
	g.x1 = p1.x;
	g.d  = d;
	g.s  = 1.0 / dx;
	g.o  = -(double)p0.x / dx;

	// Same polynomial expanded in x instead of t
	double s = g.s;
	double o = g.o;
	g.gl = {
		d[0] + o * (d[1] + o * (d[2] + o * d[3])),
		s * (d[1] + o * (2.0 * d[2] + 3.0 * o * d[3])),
		s * s * (d[2] + 3.0 * o * d[3]),
		s * s * s * d[3],
	};

	double eps = 1e-6 * peak(d);
	foreach (k, v : d) g.c[k] = math::abs(v) <= eps ? 0.0f : (float)v;

	for (int k = 3; k > 0 && g.deg == 0; k--) if (g.c[k] != 0.0f) g.deg = k;
	while (g.low < g.deg && g.c[g.low] == 0.0f) g.low++;

	g.remap = p0.x != 0.0f || dx != 1.0;
	return g;
}

fn bool same_poly(Seg* a, Seg* b) @local
{
	double tol = 1e-6 * peak(b.gl, peak(a.gl));
	foreach (k, v : a.gl) if (math::abs(v - b.gl[k]) > tol) return false;
	return true;
}

// Run k must mirror run (count-1-k) about x = sx/2
fn Sym detect_symmetry(Seg[] runs, int count, double sx, double sy) @local
{
	bool even = true;
	bool point = true;
	double xtol = 1e-6 * math::max(1.0, math::abs(sx));

	for (int k = 0; k < count; k++)
	{
		Seg* a = &runs[k];
		Seg* b = &runs[count - 1 - k];

		if (math::abs((double)a.x0 + b.x1 - sx) > xtol) return Sym.NONE;
		if (math::abs((double)a.x1 + b.x0 - sx) > xtol) return Sym.NONE;

		// b's polynomial read backwards (t -> 1 - t)
		double[4] bd = b.d;
		double[4] e = {
			bd[0] + bd[1] + bd[2] + bd[3],
			-(bd[1] + 2.0 * bd[2] + 3.0 * bd[3]),
			bd[2] + 3.0 * bd[3],
			-bd[3],
		};

		double tol = 1e-6 * peak(e, peak(a.d, math::abs(sy)));
		foreach (q, v : a.d)
		{
			double mirrored = q == 0 ? sy - e[0] : -e[q];
			if (math::abs(v - e[q]) > tol)      even = false;
			if (math::abs(v - mirrored) > tol)  point = false;
		}
		if (!even && !point) return Sym.NONE;
	}
	return even ? Sym.EVEN : Sym.POINT;
}

// Largest |value|; at least 'floor'; used for relative tolerances
fn double peak(double[4] a, double floor = 1.0) @local
{
	double m = floor;
	foreach (v : a) m = math::max(m, math::abs(v));
	return m;
}

// ================================
// Local: Printing
// ================================

// if / else if / else over runs[0..count); 'assign' is "return ", "r = " or "float r = "
fn void emit_chain(DString* s, Seg[] runs, int count, String xv, String assign) @local
{
	if (count == 1)
	{
		emit_segment(s, &runs[0], "    ", xv, assign);
		return;
	}
	for (int k = 0; k < count; k++)
	{
		Seg* g = &runs[k];
		if (k == count - 1)  { s.append("    else\n"); }
		else if (k == 0)     { s.appendf("    if (%s < %s)\n", xv, num(g.x1)); }
		else                 { s.appendf("    else if (%s < %s)\n", xv, num(g.x1)); }

		s.append("    {\n");
		emit_segment(s, g, "        ", xv, assign);
		s.append("    }\n");
	}
}

fn void emit_segment(DString* s, Seg* g, String ind, String xv, String assign) @local
{
	String v = xv;
	if (g.remap && g.deg > 0)
	{
		s.appendf("%sfloat t = %s;\n", ind, affine_expr(g, xv));
		v = "t";
	}
	s.appendf("%s%s%s;\n", ind, assign, poly_expr(g, v));
}

// t = xv*s + o
fn String affine_expr(Seg* g, String xv) @local
{
	float sc = (float)g.s;
	String m = sc == 1.0f ? xv : string::tformat("%s*%s", xv, num(sc));
	return add_term(m, (float)g.o);
}

// Horner on c[low..deg], times v^low
fn String poly_expr(Seg* g, String v) @local
{
	if (g.deg == 0) return num(g.c[0]);

	float top = g.c[g.deg];
	String lead = top == 1.0f ? "" : top == -1.0f ? "-" : string::tformat("%s*", num(top));

	// Single term: c * v^low
	if (g.deg == g.low) return string::tformat("%s%s", lead, power(v, g.low));

	String e = string::tformat("%s%s", lead, v);
	for (int i = g.deg - 1; i >= g.low; i--)
	{
		if (i < g.deg - 1) e = string::tformat("(%s)*%s", e, v);
		e = add_term(e, g.c[i]);
	}
	if (g.low > 0) e = string::tformat("%s*(%s)", power(v, g.low), e);
	return e;
}

// "e + c" / "e - c", or "e" when c == 0
fn String add_term(String e, float c) @local
{
	if (c == 0.0f) return e;
	return c < 0.0f ? string::tformat("%s - %s", e, num(-c)) : string::tformat("%s + %s", e, num(c));
}

// "v*v*v"
fn String power(String v, int k) @local
{
	String r = v;
	for (int i = 1; i < k; i++) r = string::tformat("%s*%s", r, v);
	return r;
}

// "c - v", or "-v" when c == 0
fn String sub_from(double c, String v) @local
{
	float f = (float)c;
	return f == 0.0f ? string::tformat("-%s", v) : string::tformat("%s - %s", num(f), v);
}

// Shortest-safe float literal that is always valid GLSL
fn String num(float v) @local
{
	String t = string::tformat("%.9g", v);
	foreach (ch : t) if (ch == '.' || ch == 'e') return t;
	return string::tformat("%s.0", t);
}
