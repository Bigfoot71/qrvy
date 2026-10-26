module qrvy;

import std::math;
import raylib6;

// ================================
// Public: Curve Definitions
// ================================

typedef Point = Vec3;

// ================================
// Public: Curve Functions
// ================================

fn void curve_draw(Point[] points, RLRectangle dest, float thickness, RLColor color)
{
	if (points.len < 2) return;

	rl::gl_begin(rl::RL_QUADS);
	rl::gl_color4ub(...color);

	Vec2 prev = points[0].transform(dest);

	for (int i = 0; i < points.len - 1; i++)
	{
		Point a = points[i    ];
		Point b = points[i + 1];

		float ma = tangent(points, i    );
		float mb = tangent(points, i + 1);

		Vec2 sa = a.transform(dest);
		Vec2 sb = b.transform(dest);
		int steps = (int)math::clamp((sb - sa).length() / 6.0f, 4.0f, 128.0f);

		for (int s = 1; s <= steps; s++)
		{
			float t = (float)s / (float)steps;
			Vec2 cur = to_screen(bezier_eval(a.xy, b.xy, ma, mb, t), dest);
			quad_line(prev, cur, thickness);
			prev = cur;
		}
	}

	rl::gl_end();
}

// ================================
// Public: Point Methods
// ================================

fn Vec2 Point.transform(self, RLRectangle dest) @inline
{
	return to_screen(self.xy, dest);
}

// ================================
// Local: Curve Functions
// ================================

fn Vec2 to_screen(Vec2 p, RLRectangle dest) @local @inline
{
	return math::fma((Vec2){ p.x, 1.0f - p.y }, dest.size, dest.origin);
}

fn float tangent(Point[] pts, int i) @local
{
	Vec2 p = pts[i].xy;
	float m;

	if (i == 0)
	{
		Vec2 n = pts[1].xy;
		m = (n.y - p.y) / math::max(n.x - p.x, 0.00001f);
	}
	else if (i == pts.len - 1)
	{
		Vec2 q = pts[i - 1].xy;
		m = (p.y - q.y) / math::max(p.x - q.x, 0.00001f);
	}
	else
	{
		Vec2 q = pts[i - 1].xy;
		Vec2 n = pts[i + 1].xy;

		if ((p.y - q.y) * (n.y - p.y) <= 0.0f)
		{
			m = 0.0f;
		}
		else
		{
			m = (n.y - q.y) / math::max(n.x - q.x, 0.00001f);
		}
	}

	float z = math::clamp(pts[i].z, -1.0f, 1.0f);
	return m * (1.0f - z);
}

fn Vec2 bezier_eval(Vec2 a, Vec2 b, float ma, float mb, float t) @local @inline
{
	float dx = b.x - a.x;
	Vec2 c0 = { a.x + dx / 3.0f,        a.y + ma * dx / 3.0f };
	Vec2 c1 = { a.x + dx * 2.0f / 3.0f, b.y - mb * dx / 3.0f };

	float u = 1.0f - t;
	return a  * (u * u * u)
	     + c0 * (3.0f * u * u * t)
	     + c1 * (3.0f * u * t * t)
	     + b  * (t * t * t);
}

fn void quad_line(Vec2 p0, Vec2 p1, float thickness) @local
{
	Vec2 d = p1 - p0;
	float l = d.length();
	if (l < 1e-4f) return;

	Vec2 dir = d / l;
	float half = thickness * 0.5f;
	Vec2 n = dir.yx * { -half, half };

	rl::gl_vertex2f(p0.x - n.x, p0.y - n.y);
	rl::gl_vertex2f(p0.x + n.x, p0.y + n.y);
	rl::gl_vertex2f(p1.x + n.x, p1.y + n.y);
	rl::gl_vertex2f(p1.x - n.x, p1.y - n.y);
}
