module qrvy;

import std::math;

// ================================
// Public: Shader Functions
// ================================

fn void curve_to_glsl(DString* s, Point[] pts, String name)
{
	s.appendf("float %s(float x)\n{\n", name);
	s.appendf("    x = clamp(x, %s, %s);\n", num(pts[0].x), num(pts[^1].x));

	int n = (int)pts.len - 1;
	for (int i = 0; i < n; i++)
	{
		Vec2 p0 = pts[i].xy;
		Vec2 p1 = pts[i + 1].xy;
		float dx = p1.x - p0.x;
		float dy = p1.y - p0.y;
		float ma = curve_tangent(pts, i);
		float mb = curve_tangent(pts, i + 1);

		float a = -2.0f * dy + dx * (ma + mb);
		float b =  3.0f * dy - dx * (2.0f * ma + mb);
		float c =  dx * ma;
		float d =  p0.y;

		bool last = i == n - 1;
		s.append("    ");
		if (!last) s.appendf("if (x < %s) ", num(p1.x));

		String v = "x";
		if (p0.x != 0.0f || dx != 1.0f)
		{
			s.appendf("{ float t = (x - %s) / %s; return ", num(p0.x), num(dx));
			v = "t";
		}
		else
		{
			s.append("return ");
		}

		float eps = 1e-6f;

		switch (true)
		{
			case math::abs(a) > eps: s.appendf("((%s*%s + %s)*%s + %s)*%s + %s", num(a), v, num(b), v, num(c), v, num(d));
			case math::abs(b) > eps: s.appendf("(%s*%s + %s)*%s + %s", num(b), v, num(c), v, num(d));
			case math::abs(c) > eps: s.appendf("%s*%s + %s", num(c), v, num(d));
			default:                 s.appendf("%s", num(d));
		}

		s.append(v == "t" ? "; }\n" : ";\n");
	}

	s.append("}\n");
}

// ================================
// Local: Shader Functions
// ================================

fn String num(float v) @local
{
	String t = string::tformat("%g", v);
	foreach (ch : t)
	{
		if (ch == '.' || ch == 'e') return t;
	}
	return string::tformat("%s.0", t);
}
