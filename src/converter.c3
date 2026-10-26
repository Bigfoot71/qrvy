module qrvy;

import std::math;

fn String easing_to_glsl(Allocator alloc, Point[] pts, String name)
{
	DString s;
	s.init(alloc);
	s.appendf("float %s(float x)\n{\n", name);
	s.appendf("    x = clamp(x, %g, %g);\n", pts[0].x, pts[^1].x);

	int n = (int)pts.len - 1;
	for (int i = 0; i < n; i++)
	{
		Vec2 p0 = pts[i].xy;
		Vec2 p1 = pts[i + 1].xy;
		float dx = p1.x - p0.x;
		float dy = p1.y - p0.y;
		float ma = tangent(pts, i);
		float mb = tangent(pts, i + 1);

		float a = -2.0f * dy + dx * (ma + mb);
		float b =  3.0f * dy - dx * (2.0f * ma + mb);
		float c =  dx * ma;
		float d =  p0.y;

		bool last = i == n - 1;
		s.append("    ");
		if (!last) s.appendf("if (x < %g) ", p1.x);

		String v = "x";
		if (p0.x != 0.0f || dx != 1.0f)
		{
			s.appendf("{ float t = (x - %g) / %g; return ", p0.x, dx);
			v = "t";
		}
		else
		{
			s.append("return ");
		}

		float eps = 1e-6f;

		switch (true)
		{
			case math::abs(a) > eps: s.appendf("((%g*%s + %g)*%s + %g)*%s + %g", a, v, b, v, c, v, d);
			case math::abs(b) > eps: s.appendf("(%g*%s + %g)*%s + %g", b, v, c, v, d);
			case math::abs(c) > eps: s.appendf("%g*%s + %g", c, v, d);
			default:                 s.appendf("%g", d);
		}

		s.append(v == "t" ? "; }\n" : ";\n");
	}

	s.append("}\n");
	return s.copy_str(alloc);
}
